import SwiftUI

/// Main settings view with tab navigation, styled to match the
/// notebook dashboard panel.
@MainActor
struct SettingsView: View {
    let appState: AppState
    @State private var selectedTab: SettingsTab = .providers

    @Environment(\.colorScheme) private var colorScheme

    private var palette: NotebookPalette {
        ColorTheme.palette(for: colorScheme)
    }

    enum SettingsTab: String, CaseIterable {
        case providers = "Providers"
        case display = "Display"
        case general = "General"
    }

    private var isGlass: Bool {
        appState.appearanceMode.isGlass
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Rectangle()
                .fill(isGlass ? Color.primary.opacity(0.12) : palette.hairline)
                .frame(height: 1)

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Tab content
            ScrollView {
                Group {
                    switch selectedTab {
                    case .providers:
                        ProvidersSettingsView(appState: appState)
                    case .display:
                        DisplaySettingsView(appState: appState)
                    case .general:
                        GeneralSettingsView(appState: appState)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(isGlass ? Color.clear : palette.panel)
    }

    private var headerView: some View {
        HStack(spacing: 10) {
            Button {
                appState.showingSettings = false
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 12))
                }
                .foregroundStyle(palette.section)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Back to dashboard")

            Spacer()

            Text("Settings")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.title)

            Spacer()

            // Mirrors the back control's width so the title stays centered.
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text("Back")
                    .font(.system(size: 12))
            }
            .hidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Shared section header

/// Section heading used across settings tabs, matching the dashboard's
/// provider-name treatment.
struct SettingsSectionHeader: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(ColorTheme.palette(for: colorScheme).section)
    }
}

/// Hairline separator matching the dashboard. Over glass it becomes a
/// tonal overlay so it never reads as a pasted opaque line.
struct SettingsHairline: View {
    var isGlass: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(
                isGlass
                    ? Color.primary.opacity(0.12)
                    : ColorTheme.palette(for: colorScheme).hairline
            )
            .frame(height: 1)
    }
}
