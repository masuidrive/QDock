import SwiftUI

/// Main dashboard view shown in the popover
@MainActor
struct DashboardView: View {
    let appState: AppState
    @State private var selectedProviderIndex: Int = 0

    private struct ProviderTab: Identifiable {
        let id: String
        let index: Int
        let name: String
        let iconName: String
    }

    private var activeProviders: [any QuotaProvider] {
        appState.providerManager.activeProviders
    }

    private var selectedProvider: (any QuotaProvider)? {
        guard !activeProviders.isEmpty else { return nil }
        let index = min(selectedProviderIndex, activeProviders.count - 1)
        return activeProviders[index]
    }

    private var selectedQuota: QuotaData? {
        guard let provider = selectedProvider else { return nil }
        return appState.providerManager.quotaByProvider[provider.id]
    }

    private var providerTabs: [ProviderTab] {
        activeProviders.enumerated().map { index, provider in
            ProviderTab(
                id: provider.id,
                index: index,
                name: provider.name,
                iconName: provider.iconName
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            if activeProviders.isEmpty {
                EmptyStateView {
                    appState.showingSettings = true
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Provider switcher (only when multiple providers)
                        if activeProviders.count > 1 {
                            providerSwitcher
                        }

                        if let quota = selectedQuota {
                            // Hero section — tappable to go to detail
                            Button {
                                appState.selectedProvider = selectedProvider
                            } label: {
                                heroSection(quota: quota)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, activeProviders.count > 1 ? 4 : 16)

                            // Window cards (exclude session if hero already shows it)
                            ForEach(quota.windowsExcludingSessionWhenAvailable) { window in
                                UsageCardView(window: window)
                            }

                            // Paid overage state, when enabled
                            if let credits = quota.usageCredits {
                                UsageCreditsCardView(credits: credits)
                            }

                            // Account info footer
                            accountFooter(quota: quota)
                        } else if let provider = selectedProvider,
                                  let error = appState.providerManager.errorsByProvider[provider.id] {
                            // Error state
                            VStack(spacing: 8) {
                                Spacer().frame(height: 40)
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Spacer().frame(height: 40)
                            }
                            .padding(.horizontal, 8)
                        } else if let provider = selectedProvider,
                                  appState.providerManager.loadingProviders.contains(provider.id) {
                            // Loading
                            VStack {
                                Spacer().frame(height: 60)
                                ProgressView("Loading...")
                                Spacer().frame(height: 60)
                            }
                        } else {
                            // No data yet
                            VStack {
                                Spacer().frame(height: 60)
                                Text("No data available")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Spacer().frame(height: 60)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }

            Divider()

            // Footer
            footerView
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            RefreshButton(isRefreshing: appState.refreshService.isRefreshing) {
                Task { await appState.manualRefresh() }
            }

            Spacer()

            VStack(spacing: 1) {
                Text("QDock")
                    .font(.headline)

                if let lastRefresh = appState.refreshService.timeSinceLastRefresh {
                    Text("Updated \(lastRefresh)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                appState.showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Provider Switcher

    private var providerSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(providerTabs) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedProviderIndex = tab.index
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 10))
                        Text(tab.name)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedProviderIndex == tab.index
                                  ? Color.primary.opacity(0.1)
                                  : Color.clear)
                    )
                    .foregroundStyle(selectedProviderIndex == tab.index ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
        )
        .padding(.top, 8)
    }

    // MARK: - Hero Section

    private func heroSection(quota: QuotaData) -> some View {
        let heroWindow = quota.sessionWindow ?? quota.primaryWindow
        let heroPercent = heroWindow?.usagePercent ?? 0
        let isCritical = heroPercent >= 90

        return VStack(spacing: 8) {
            ZStack {
                ProgressRingView(
                    progress: heroPercent,
                    size: 100,
                    lineWidth: 12
                )
                .if(isCritical) { view in
                    view.glowEffect(color: ColorTheme.colorForUsage(heroPercent))
                }

                VStack(spacing: 2) {
                    AnimatedPercentage(percent: heroPercent, fontSize: 28)

                    if let plan = quota.planName {
                        Text(plan)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let countdown = heroWindow?.resetCountdown {
                Text("Resets in \(countdown)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Subtle tap hint
            Text("Tap for details")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Account Footer

    private func accountFooter(quota: QuotaData) -> some View {
        HStack(spacing: 6) {
            if let email = quota.accountEmail ?? (selectedProvider as? ClaudeCodeProvider)?.accountEmail {
                Image(systemName: "person.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(email)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            if let plan = quota.planName {
                Text(plan)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.claudeAccent.opacity(0.15))
                    )
                    .foregroundStyle(Color.claudeAccent)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 8) {
            if let version = appState.availableUpdateVersion {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Update \(version) available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()

                    if appState.isInstallingUpdate {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Button("Install") {
                            Task { await appState.installAvailableUpdate() }
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                    }

                    if let updateURL = appState.availableUpdateURL {
                        Link("Manual", destination: updateURL)
                            .font(.caption2)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                )
            }

            if let installedVersion = appState.installedUpdateVersion {
                Text("Update \(installedVersion) installed. Restart QDock to apply.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
            }

            if let installError = appState.updateInstallError {
                Text(installError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
            }

            HStack {
                Button("Quit QDock") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                if appState.isCheckingForUpdates {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Button("Check updates") {
                        Task { await appState.checkForUpdates(force: true) }
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                if appState.availableUpdateVersion == nil, appState.installedUpdateVersion == nil {
                    Text("Up to date")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text("v\(appState.currentAppVersion)")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Conditional Modifier

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
