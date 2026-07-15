import SwiftUI

/// Main dashboard view shown in the popover.
///
/// Mirrors the popover design on qdock.saidaltan.com: a flat notebook
/// panel listing every active provider as a section of usage rows, each
/// row carrying a thin color-coded bar and a mono percentage. Follows
/// the popover appearance (system, dark, or light).
@MainActor
struct DashboardView: View {
    let appState: AppState

    @Environment(\.colorScheme) private var colorScheme

    private var palette: NotebookPalette {
        ColorTheme.palette(for: colorScheme)
    }

    /// Glass mode keeps the popover's native translucent material, so the
    /// panel goes clear and separators/strips become tonal overlays.
    private var isGlass: Bool {
        appState.appearanceMode.isGlass
    }

    private var panelFill: Color {
        isGlass ? .clear : palette.panel
    }

    private var hairlineFill: Color {
        isGlass ? Color.primary.opacity(0.12) : palette.hairline
    }

    private var liftedFill: Color {
        isGlass ? Color.primary.opacity(0.05) : palette.lifted
    }

    private var activeProviders: [any QuotaProvider] {
        appState.providerManager.activeProviders
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if activeProviders.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    headerView
                }
                .padding(16)
                EmptyStateView {
                    appState.showingSettings = true
                }
                .frame(minHeight: 300)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    headerView

                    ForEach(Array(activeProviders.enumerated()), id: \.element.id) { index, provider in
                        providerSection(provider)

                        if index < activeProviders.count - 1 {
                            Rectangle()
                                .fill(hairlineFill)
                                .frame(height: 1)
                                .padding(.vertical, 10)
                        }
                    }

                    refreshCadenceLine
                }
                .padding(16)
            }

            Rectangle()
                .fill(hairlineFill)
                .frame(height: 1)

            footerView
                .background(liftedFill)
        }
        .background(panelFill)
    }

    // MARK: - Header ("Usage" | updated · refresh · settings)

    private var headerView: some View {
        HStack(spacing: 10) {
            Text("Usage")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.title)

            Spacer()

            if let updated = updatedText {
                Text(updated)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.meta)
            }

            RefreshButton(isRefreshing: appState.refreshService.isRefreshing) {
                Task { await appState.manualRefresh() }
            }

            Button {
                appState.showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.section)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.bottom, 12)
    }

    // MARK: - Provider section

    @ViewBuilder
    private func providerSection(_ provider: any QuotaProvider) -> some View {
        let quota = appState.providerManager.quotaByProvider[provider.id]

        VStack(alignment: .leading, spacing: 0) {
            providerNameRow(provider, quota: quota)
                .padding(.bottom, 6)

            if let quota {
                ForEach(quota.windows) { window in
                    usageRow(
                        label: Self.siteLabel(for: window),
                        reset: window.resetCountdown,
                        percent: window.usagePercent
                    )
                }

                if let credits = quota.usageCredits, let utilization = credits.utilization {
                    usageRow(
                        label: "Usage credits",
                        reset: nil,
                        percent: utilization
                    )
                }
            } else if let error = appState.providerManager.errorsByProvider[provider.id] {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.meta)
                    .padding(.vertical, 4)
            } else if appState.providerManager.loadingProviders.contains(provider.id) {
                Text("loading…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.meta)
                    .padding(.vertical, 4)
            } else {
                Text("no data yet")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.meta)
                    .padding(.vertical, 4)
            }
        }
    }

    private func providerNameRow(_ provider: any QuotaProvider, quota: QuotaData?) -> some View {
        HStack(spacing: 6) {
            Text(provider.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.section)

            Spacer()

            if quota?.isStale == true {
                Text("cached")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.meta)
            }

            if let plan = quota?.planName {
                Text(plan)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.meta)
            }
        }
    }

    // MARK: - Usage row (label · bar · percent)

    private func usageRow(label: String, reset: String?, percent: Double) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.label)

                if let reset {
                    Text("resets in \(reset)")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.meta)
                }
            }

            Spacer(minLength: 8)

            NotebookBarView(
                percent: percent,
                fill: palette.usageBar(percent),
                track: palette.barTrack
            )

            Text("\(Int(percent.rounded()))%")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.usageText(percent))
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    /// Maps provider window names to the site's compact label style
    /// ("Session (5h)" → "Session · 5h", "Opus Weekly" → "Week · Opus").
    static func siteLabel(for window: QuotaWindow) -> String {
        let name = window.displayName

        let sessionIds: Set<String> = ["session", "five_hour"]
        if sessionIds.contains(window.id) || name.lowercased().hasPrefix("session") {
            if let minutes = window.windowDurationMinutes, minutes > 0 {
                let hours = minutes / 60
                return hours > 0 ? "Session · \(hours)h" : "Session · \(minutes)m"
            }
            return "Session"
        }

        if name == "Weekly" { return "Week" }
        if name == "Weekly (All Models)" { return "Week · all models" }
        if name.hasSuffix(" Weekly") {
            return "Week · " + name.dropLast(" Weekly".count)
        }
        if name.hasPrefix("Weekly ") {
            return "Week · " + name.dropFirst("Weekly ".count)
        }

        return name
            .replacingOccurrences(of: " (", with: " · ")
            .replacingOccurrences(of: ")", with: "")
    }

    // MARK: - Refresh metadata (site-style compact strings)

    /// "updated 12s ago" like the site, instead of the wordy system formatter.
    private var updatedText: String? {
        guard let date = appState.refreshService.lastRefreshDate else { return nil }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "updated \(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "updated \(minutes)m ago" }
        return "updated \(minutes / 60)h ago"
    }

    private var refreshCadenceLine: some View {
        let interval = Int(appState.refreshService.refreshInterval)

        return HStack {
            Spacer()
            Text(interval > 0 ? "refreshing every \(interval)s" : "manual refresh")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.meta)
        }
        .padding(.top, 10)
    }

    // MARK: - Footer (app chrome, on a lifted surface for depth)

    private var footerView: some View {
        VStack(spacing: 8) {
            if let version = appState.availableUpdateVersion {
                HStack(spacing: 8) {
                    Text("Update \(version) available")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.label)

                    Spacer()

                    if appState.isInstallingUpdate {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Button("Install") {
                            Task { await appState.installAvailableUpdate() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.usageText(60))
                    }

                    if let updateURL = appState.availableUpdateURL {
                        Link("Manual", destination: updateURL)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.section)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isGlass ? Color.primary.opacity(0.06) : palette.panel)
                )
            }

            if let installedVersion = appState.installedUpdateVersion {
                Text("Update \(installedVersion) installed. Restart QDock to apply.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.meta)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let installError = appState.updateInstallError {
                Text(installError)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.usageText(80))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button("Quit QDock") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(palette.section)

                Spacer()

                if appState.isCheckingForUpdates {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Button("Check updates") {
                        Task { await appState.checkForUpdates(force: true) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.meta)
                }

                if appState.availableUpdateVersion == nil, appState.installedUpdateVersion == nil {
                    Text("Up to date")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.meta)
                }

                Text("v\(appState.currentAppVersion)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.meta)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Notebook bar (site-style thin progress bar)

/// The site's 96x4 usage bar: hairline track, color-coded fill,
/// width animates in without distorting the rounded caps.
struct NotebookBarView: View {
    let percent: Double
    let fill: Color
    let track: Color

    @State private var displayedPercent: Double = 0

    private static let trackWidth: CGFloat = 96

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(track)

            RoundedRectangle(cornerRadius: 2)
                .fill(fill)
                .frame(width: Self.trackWidth * CGFloat(max(0, min(displayedPercent, 100)) / 100))
        }
        .frame(width: Self.trackWidth, height: 4)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) {
                displayedPercent = percent
            }
        }
        .onChange(of: percent) { _, newValue in
            withAnimation(.easeInOut(duration: 0.3)) {
                displayedPercent = newValue
            }
        }
    }
}
