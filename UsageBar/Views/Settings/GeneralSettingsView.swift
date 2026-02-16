import SwiftUI
import ServiceManagement

/// General application settings
struct GeneralSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var launchAtLoginEnabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Launch at login
            VStack(alignment: .leading, spacing: 6) {
                Text("Startup")
                    .font(.callout)
                    .fontWeight(.medium)

                Toggle("Launch at login", isOn: $launchAtLoginEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: launchAtLoginEnabled) { _, newValue in
                        toggleLaunchAtLogin(newValue)
                    }

                Text("Automatically start UsageBar when you log in to your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // About
            VStack(alignment: .leading, spacing: 6) {
                Text("About")
                    .font(.callout)
                    .fontWeight(.medium)

                VStack(alignment: .leading, spacing: 4) {
                    aboutRow("Version", value: "1.0.0")
                    aboutRow("Platform", value: "macOS 14+")
                    aboutRow("Framework", value: "SwiftUI")
                }
            }

            Divider()

            // Data management
            VStack(alignment: .leading, spacing: 6) {
                Text("Data")
                    .font(.callout)
                    .fontWeight(.medium)

                Button("Clear All API Keys") {
                    clearAllKeys()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(.red)

                Text("Remove all stored API keys from Keychain. You'll need to re-enter them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        } catch {
            // Revert on failure
            launchAtLoginEnabled = !enable
        }
    }

    private func checkLaunchAtLoginStatus() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    private func clearAllKeys() {
        for provider in appState.providerManager.providers {
            KeychainService.shared.delete(key: "\(provider.id)-api-key")
        }
        appState.providerManager.objectWillChange.send()
    }
}
