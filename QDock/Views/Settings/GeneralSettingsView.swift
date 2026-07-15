import SwiftUI
import ServiceManagement

/// General application settings
@MainActor
struct GeneralSettingsView: View {
    let appState: AppState
    @State private var launchAtLoginEnabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Launch at login
            VStack(alignment: .leading, spacing: 6) {
                SettingsSectionHeader(text: "Startup")

                Toggle("Launch at login", isOn: $launchAtLoginEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: launchAtLoginEnabled) { _, newValue in
                        toggleLaunchAtLogin(newValue)
                    }

                Text("Automatically start QDock when you log in to your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsHairline(isGlass: appState.appearanceMode.isGlass)

            // About
            VStack(alignment: .leading, spacing: 6) {
                SettingsSectionHeader(text: "About")

                VStack(alignment: .leading, spacing: 4) {
                    aboutRow("Version", value: appState.currentAppVersion)
                    aboutRow("Platform", value: "macOS 14+")
                    aboutRow("Framework", value: "SwiftUI")
                }
            }

            Spacer()
        }
        .padding(16)
        .onAppear {
            checkLaunchAtLoginStatus()
        }
    }

    private func aboutRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }

    private func toggleLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            appState.launchAtLogin = enable
        } catch {
            // Revert on failure
            launchAtLoginEnabled = !enable
        }
    }

    private func checkLaunchAtLoginStatus() {
        let enabled = SMAppService.mainApp.status == .enabled
        launchAtLoginEnabled = enabled
        appState.launchAtLogin = enabled
    }
}
