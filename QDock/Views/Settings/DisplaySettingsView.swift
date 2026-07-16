import SwiftUI
import Observation

/// Display preferences settings
@MainActor
struct DisplaySettingsView: View {
    @Bindable var appState: AppState

    private var menuBarUsageSource: MenuBarUsageSource {
        MenuBarUsageSource(rawValue: appState.menuBarUsageSourceRaw) ?? .highestUsage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Appearance
            VStack(alignment: .leading, spacing: 6) {
                SettingsSectionHeader(text: "Appearance")

                Picker("", selection: $appState.appearanceModeRaw) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text("System follows macOS. Dark and Light force the popover's theme. Glass uses the native translucent material (Liquid Glass on macOS 26+).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsHairline(isGlass: appState.appearanceMode.isGlass)

            // Refresh interval
            VStack(alignment: .leading, spacing: 6) {
                SettingsSectionHeader(text: "Auto-Refresh Interval")

                Picker("", selection: $appState.refreshIntervalSeconds) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Text("How often quota data is refreshed. Intervals below 2 minutes are not offered to stay within API rate limits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsHairline(isGlass: appState.appearanceMode.isGlass)

            // Menu bar display
            VStack(alignment: .leading, spacing: 6) {
                SettingsSectionHeader(text: "Menu Bar Display")

                Toggle("Show usage percent in menu bar", isOn: $appState.showPercentInMenuBar)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Picker("Usage source", selection: $appState.menuBarUsageSourceRaw) {
                    ForEach(MenuBarUsageSource.allCases) { source in
                        Text(source.displayName).tag(source.rawValue)
                    }
                }
                .pickerStyle(.menu)

                if menuBarUsageSource == .selectedProvider {
                    if appState.availableMenuBarProviders.isEmpty {
                        Text("Enable at least one detected provider to choose a menu bar source.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Picker("Provider", selection: $appState.menuBarProviderId) {
                            ForEach(appState.availableMenuBarProviders, id: \.id) { provider in
                                Text(provider.name).tag(provider.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Text("Menu bar percent and icon color are based on session limits from the source selected above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsHairline(isGlass: appState.appearanceMode.isGlass)

            // Usage alerts
            VStack(alignment: .leading, spacing: 6) {
                SettingsSectionHeader(text: "Notifications")

                Toggle("Alert at 70% and 90% usage", isOn: $appState.usageAlertsEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Text("Each limit window notifies once per threshold and re-arms after it resets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .onAppear {
            appState.ensureMenuBarProviderSelection()
            appState.emitMenuBarPresentationIfNeeded()
        }
    }
}
