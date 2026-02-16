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

    private var isLocalProvider: Bool {
        provider.id == "claude-code-local"
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

                if isLocalProvider {
                    Text("AUTO")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { provider.isEnabled },
                    set: { _ in appState.providerManager.toggleProvider(provider.id) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            // Description
            Text(provider.apiKeyDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isLocalProvider {
                // Claude Code local — show status instead of API key input
                claudeCodeStatusView
            } else {
                // API-based providers — show key input
                apiKeyInputView
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

    // MARK: - Claude Code Status View

    @State private var customPath: String = ""
    @State private var showCustomPath: Bool = false

    @ViewBuilder
    private var claudeCodeStatusView: some View {
        let ccProvider = provider as? ClaudeCodeProvider

        VStack(alignment: .leading, spacing: 8) {
            // Detection strategy badge
            if let result = ccProvider?.detectionResult {
                HStack(spacing: 6) {
                    Image(systemName: result.isDetected ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(result.isDetected ? .green : .orange)
                        .font(.caption)
                    Text(strategyLabel(result.strategy))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(result.isDetected ? .green : .orange)
                }

                Text(result.message)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Login status
            HStack(spacing: 6) {
                Image(systemName: ccProvider?.isLoggedIn == true ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(ccProvider?.isLoggedIn == true ? .green : .orange)
                    .font(.caption)
                Text(ccProvider?.isLoggedIn == true ? "Logged in via OAuth" : "Not logged in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Account info
            if let account = ccProvider?.accountInfo {
                HStack(spacing: 6) {
                    Image(systemName: "person.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let email = account.emailAddress {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let org = account.organizationName {
                        Text("(\(org))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Subscription
            if let sub = ccProvider?.subscriptionType {
                HStack(spacing: 6) {
                    Image(systemName: "star.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(sub.capitalized) plan")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Data source info
            if let result = ccProvider?.detectionResult {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(result.configDir?.path ?? "Not found")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let cli = result.cliPath {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(cli)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Fallback indicator
                if !result.hasSessions && result.hasOAuthCredentials {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("Using API fallback (no local session files)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    .padding(.top, 2)
                }
            }

            Divider()

            // Custom path override
            DisclosureGroup("Custom data path", isExpanded: $showCustomPath) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Override the auto-detected path if Claude Code data is in a non-standard location.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 6) {
                        TextField("~/.claude", text: $customPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))

                        Button("Apply") {
                            ccProvider?.setCustomPath(customPath)
                            appState.providerManager.objectWillChange.send()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(customPath.isEmpty)

                        Button("Reset") {
                            customPath = ""
                            ccProvider?.setCustomPath("")
                            appState.providerManager.objectWillChange.send()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if let envVar = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
                        Text("CLAUDE_CONFIG_DIR: \(envVar)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear {
            customPath = ccProvider?.detector.customConfigPath ?? ""
        }
    }

    private func strategyLabel(_ strategy: ClaudeCodeDetector.Strategy) -> String {
        switch strategy {
        case .defaultPath: return "Detected at ~/.claude"
        case .envVariable: return "Detected via CLAUDE_CONFIG_DIR"
        case .customPath: return "Using custom path"
        case .cliBinary: return "CLI found, awaiting sessions"
        case .keychainOnly: return "Keychain only (API fallback)"
        case .none: return "Not detected"
        }
    }

    // MARK: - API Key Input View

    @ViewBuilder
    private var apiKeyInputView: some View {
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

    private func validateKey() async {
        isValidating = true
        validationResult = nil

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
