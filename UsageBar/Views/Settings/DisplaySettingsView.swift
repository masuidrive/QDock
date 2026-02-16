import SwiftUI

/// Display preferences settings
struct DisplaySettingsView: View {
    @ObservedObject var appState: AppState
    @AppStorage("refreshIntervalSeconds") private var refreshInterval: Double = 900
    @AppStorage("showCostInMenuBarPref") private var showCostInMenuBar: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Refresh interval
            VStack(alignment: .leading, spacing: 6) {
                Text("Auto-Refresh Interval")
                    .font(.callout)
                    .fontWeight(.medium)

                Picker("", selection: $refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: refreshInterval) { _, newValue in
                    appState.refreshService.updateInterval(newValue)
                }

                Text("How often usage data is automatically refreshed. Data from Anthropic has ~5 min delay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Menu bar display
            VStack(alignment: .leading, spacing: 6) {
                Text("Menu Bar Display")
                    .font(.callout)
                    .fontWeight(.medium)

                Toggle("Show total cost in menu bar", isOn: $showCostInMenuBar)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: showCostInMenuBar) { _, newValue in
                        appState.showCostInMenuBar = newValue
                    }

                Text("Display today's total cost next to the menu bar icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
    }
}
