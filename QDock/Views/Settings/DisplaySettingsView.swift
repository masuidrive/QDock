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
            // Refresh interval
            VStack(alignment: .leading, spacing: 6) {
                Text("Auto-Refresh Interval")
                    .font(.callout)
                    .fontWeight(.medium)

                Picker("", selection: $appState.refreshIntervalSeconds) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Text("How often quota data is refreshed. Higher usage triggers more frequent checks automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Menu bar display
            VStack(alignment: .leading, spacing: 6) {
                Text("Menu Bar Display")
                    .font(.callout)
                    .fontWeight(.medium)

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

            Spacer()
        }
        .padding(16)
        .onAppear {
            appState.ensureMenuBarProviderSelection()
            appState.emitMenuBarPresentationIfNeeded()
        }
    }
}
