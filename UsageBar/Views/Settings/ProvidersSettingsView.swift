import SwiftUI

/// Provider configuration settings
struct ProvidersSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            ForEach(appState.providerManager.providers, id: \.id) { provider in
                ProviderSettingCard(
                    provider: provider,
                    appState: appState
                )
            }
        }
        .padding(16)
    }
}

/// Individual provider configuration card
struct ProviderSettingCard: View {
    let provider: any UsageProvider
    @ObservedObject var appState: AppState
    @State private var apiKeyInput: String = ""
    @State private var isShowingKey: Bool = false
    @State private var isValidating: Bool = false
    @State private var validationResult: ValidationResult?

    enum ValidationResult {
        case success
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Provider header
            HStack {
                Image(systemName: provider.iconName)
                    .foregroundStyle(Color(hex: provider.brandColorHex) ?? .blue)
                    .font(.system(size: 16))

                Text(provider.name)
                    .font(.callout)
                    .fontWeight(.medium)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { provider.isEnabled },
                    set: { _ in appState.providerManager.toggleProvider(provider.id) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            // API key description
            Text(provider.apiKeyDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // API key input
            HStack(spacing: 8) {
                Group {
                    if isShowingKey {
                        TextField(provider.apiKeyPlaceholder, text: $apiKeyInput)
                    } else {
                        SecureField(provider.apiKeyPlaceholder, text: $apiKeyInput)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))

                Button {
                    isShowingKey.toggle()
                } label: {
                    Image(systemName: isShowingKey ? "eye.slash" : "eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isShowingKey ? "Hide API key" : "Show API key")
            }

            // Action buttons
            HStack {
                Button("Save") {
                    appState.providerManager.setAPIKey(apiKeyInput, for: provider.id)
                    validationResult = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(apiKeyInput.isEmpty)

                Button("Test") {
                    Task { await validateKey() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(apiKeyInput.isEmpty || isValidating)

                if isValidating {
                    ProgressView()
                        .controlSize(.mini)
                }

                Spacer()

                // Validation result
                if let result = validationResult {
                    switch result {
                    case .success:
                        Label("Valid", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .failure(let message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.primary.opacity(0.06), lineWidth: 1)
                )
        )
        .onAppear {
            apiKeyInput = appState.providerManager.getAPIKey(for: provider.id)
        }
    }

    private func validateKey() async {
        isValidating = true
        validationResult = nil

        // Temporarily save the key for validation
        appState.providerManager.setAPIKey(apiKeyInput, for: provider.id)

        do {
            let isValid = try await provider.validate()
            validationResult = isValid ? .success : .failure("Invalid key")
        } catch {
            validationResult = .failure(error.localizedDescription)
        }

        isValidating = false
    }
}
