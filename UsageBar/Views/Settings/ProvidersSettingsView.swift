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

    /// Providers that auto-detect without API key
    private var isAutoDetectedProvider: Bool {
        ["claude-code-local", "cursor", "codex"].contains(provider.id)
    }

    /// Providers that need extra config fields
    private var needsExtraConfig: Bool {
        ["copilot", "windsurf"].contains(provider.id)
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

                if isAutoDetectedProvider && provider.isConfigured {
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

            // Provider-specific config views
            switch provider.id {
            case "claude-code-local":
                claudeCodeStatusView
            case "cursor":
                cursorStatusView
            case "codex":
                codexStatusView
            case "copilot":
                copilotConfigView
                apiKeyInputView
            case "windsurf":
                windsurfStatusView
                apiKeyInputView
            default:
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

    // MARK: - Cursor Status View

    @ViewBuilder
    private var cursorStatusView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Installation status
            HStack(spacing: 6) {
                Image(systemName: CursorAuthReader.isInstalled ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(CursorAuthReader.isInstalled ? .green : .orange)
                    .font(.caption)
                Text(CursorAuthReader.isInstalled ? "Cursor installed" : "Cursor not found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Auth status
            if CursorAuthReader.accessToken != nil {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("Logged in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let userId = CursorAuthReader.userId {
                    HStack(spacing: 6) {
                        Image(systemName: "person.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(userId)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } else if CursorAuthReader.isInstalled {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Not logged in — open Cursor and sign in")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // Data source
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(CursorAuthReader.dataDir.path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    // MARK: - Codex Status View

    @ViewBuilder
    private var codexStatusView: some View {
        let codexDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
        let isInstalled = FileManager.default.fileExists(atPath: codexDir.path)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: isInstalled ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(isInstalled ? .green : .orange)
                    .font(.caption)
                Text(isInstalled ? "Codex CLI installed" : "Codex CLI not found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isInstalled {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("~/.codex/")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                // Check history file
                let historyPath = codexDir.appendingPathComponent("history.jsonl")
                let hasHistory = FileManager.default.fileExists(atPath: historyPath.path)

                HStack(spacing: 6) {
                    Image(systemName: hasHistory ? "doc.text.fill" : "doc.text")
                        .font(.caption)
                        .foregroundStyle(hasHistory ? .green : .orange)
                    Text(hasHistory ? "Session history available" : "No history.jsonl yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let config = CodexConfig.read(), let model = config.model {
                    HStack(spacing: 6) {
                        Image(systemName: "cpu")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Default model: \(model)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Copilot Config View

    @State private var copilotOrg: String = ""
    @State private var copilotUsername: String = ""

    @ViewBuilder
    private var copilotConfigView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Configure at least one: organization name (for team metrics) or GitHub username (for individual billing).")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack(spacing: 6) {
                Text("Org:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                TextField("my-org", text: $copilotOrg)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            }

            HStack(spacing: 6) {
                Text("Username:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                TextField("octocat", text: $copilotUsername)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            }

            Button("Save Config") {
                if let copilot = provider as? CopilotProvider {
                    copilot.organizationName = copilotOrg
                    copilot.username = copilotUsername
                    appState.providerManager.objectWillChange.send()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(copilotOrg.isEmpty && copilotUsername.isEmpty)
        }
        .onAppear {
            if let copilot = provider as? CopilotProvider {
                copilotOrg = copilot.organizationName
                copilotUsername = copilot.username
            }
        }
    }

    // MARK: - Windsurf Status View

    @ViewBuilder
    private var windsurfStatusView: some View {
        let isInstalled = WindsurfProvider.isInstalled

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: isInstalled ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(isInstalled ? .green : .orange)
                    .font(.caption)
                Text(isInstalled ? "Windsurf installed" : "Windsurf not found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isInstalled {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("~/.codeium/windsurf/")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Text("Enterprise service key required for detailed analytics")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
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
