import SwiftUI

/// Main settings view with tab navigation
struct SettingsView: View {
    let appState: AppState
    @State private var selectedTab: SettingsTab = .providers

    enum SettingsTab: String, CaseIterable {
        case providers = "Providers"
        case display = "Display"
        case general = "General"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

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
        .background(.ultraThinMaterial)
    }

    private var headerView: some View {
        Text("Settings")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                Button {
                    appState.showingSettings = false
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                .help("Back to dashboard")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }
}
