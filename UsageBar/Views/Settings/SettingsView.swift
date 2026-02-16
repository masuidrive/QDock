import SwiftUI

/// Main settings view with tab navigation
struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: SettingsTab = .providers

    enum SettingsTab: String, CaseIterable {
        case providers = "Providers"
        case display = "Display"
        case general = "General"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    appState.showingSettings = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Settings")
                    .font(.headline)

                Spacer()

                Color.clear.frame(width: 50)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Tab content
            ScrollView {
                switch selectedTab {
                case .providers:
                    ProvidersSettingsView(appState: appState)
                case .display:
                    DisplaySettingsView(appState: appState)
                case .general:
                    GeneralSettingsView(appState: appState)
                }
            }
        }
        .background(.ultraThinMaterial)
    }
}
