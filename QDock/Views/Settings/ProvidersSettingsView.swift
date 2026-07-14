import SwiftUI

/// Provider configuration settings
@MainActor
struct ProvidersSettingsView: View {
    let appState: AppState

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
@MainActor
struct ProviderSettingCard: View {
    let provider: any QuotaProvider
    let appState: AppState

    @State private var codexTokenInput: String = ""
    @State private var showCodexTokenInput: Bool = false

    private var providerErrorMessage: String? {
        appState.providerManager.errorsByProvider[provider.id]
    }

    var body: some View {
        let status = provider.authStatus

        VStack(alignment: .leading, spacing: 10) {
            // Provider header
            HStack {
                Image(systemName: provider.iconName)
                    .foregroundStyle(Color(hex: provider.brandColorHex) ?? .blue)
                    .font(.system(size: 16))

                Text(provider.name)
                    .font(.callout)
                    .fontWeight(.medium)

                authStatusBadge(status: status)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { provider.isEnabled },
                    set: { _ in appState.toggleProvider(provider.id) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            // Provider-specific status view
            switch provider.id {
            case "claude-code":
                claudeCodeStatusView(status: status)
            case "codex":
                codexStatusView(status: status)
            default:
                EmptyView()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
        )
        .task(id: provider.id) {
            await appState.providerManager.refreshProviderLocalState(for: provider.id)
        }
    }

    // MARK: - Auth Status Badge

    @ViewBuilder
    private func authStatusBadge(status: AuthStatus) -> some View {
        switch status {
        case .authenticated:
            Text("AUTH")
                .font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.usageGreen.opacity(0.15))
                .foregroundStyle(Color.usageGreen)
                .clipShape(Capsule())
        case .needsAuth:
            Text("SETUP")
                .font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.usageOrange.opacity(0.15))
                .foregroundStyle(Color.usageOrange)
                .clipShape(Capsule())
        case .notInstalled:
            Text("N/A")
                .font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.gray.opacity(0.15))
                .foregroundStyle(.gray)
                .clipShape(Capsule())
        }
    }

    // MARK: - Claude Code Status

    @ViewBuilder
    private func claudeCodeStatusView(status: AuthStatus) -> some View {
        let claudeProvider = provider as? ClaudeCodeProvider

        VStack(alignment: .leading, spacing: 8) {
            if let result = claudeProvider?.detectionResult {
                HStack(spacing: 6) {
                    Image(systemName: result.isDetected ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(result.isDetected ? Color.usageGreen : Color.usageOrange)
                        .font(.caption)
                    Text(result.isDetected ? "Claude detected" : "Claude not detected")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(result.isDetected ? Color.usageGreen : Color.usageOrange)
                }

                if !result.isDetected {
                    Text("Install Claude, then run `claude` in terminal.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: status.isAuthenticated ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(status.isAuthenticated ? Color.usageGreen : Color.usageOrange)
                    .font(.caption)
                Text(status.isAuthenticated ? "Authenticated" : "Not authenticated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if claudeProvider?.missingProfileScope == true {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.usageOrange)
                    Text("This token can't read usage data (missing user:profile scope). Run `claude /login` in your terminal to re-authenticate.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let email = claudeProvider?.accountEmail {
                HStack(spacing: 6) {
                    Image(systemName: "person.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let plan = claudeProvider?.planDisplayName {
                HStack(spacing: 6) {
                    Image(systemName: "star.circle")
                        .font(.caption)
                        .foregroundStyle(Color.claudeAccent)
                    Text("\(plan) plan")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if shouldShowClaudeAuthHelp(status: status) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("How to fix authentication")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }

                    Text(claudeAuthHelpMessage(status: status))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Refresh") {
                        refreshAllProviders()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.orange.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.orange.opacity(0.25), lineWidth: 0.5)
                        )
                )
            }
        }
    }

    // MARK: - Codex Status

    @ViewBuilder
    private func codexStatusView(status: AuthStatus) -> some View {
        let codexProvider = provider as? CodexProvider
        let isInstalled = codexProvider?.isInstalled ?? provider.isConfigured
        let hasManualToken = codexProvider?.hasManualToken ?? false

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: isInstalled ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(isInstalled ? Color.usageGreen : Color.usageOrange)
                    .font(.caption)
                Text(isInstalled ? "Codex installed" : "Codex not found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isInstalled {
                HStack(spacing: 6) {
                    Image(systemName: status.isAuthenticated ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(status.isAuthenticated ? Color.usageGreen : Color.usageOrange)
                        .font(.caption)
                    Text(status.isAuthenticated ? "Authenticated" : "Not authenticated")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Install Codex: npm i -g @openai/codex")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if shouldShowCodexAuthHelp(status: status) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Run `codex login`, then click Refresh.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Refresh") {
                        refreshAllProviders()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.orange.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.orange.opacity(0.25), lineWidth: 0.5)
                        )
                )
            }

            if isInstalled && (!status.isAuthenticated || hasManualToken) {
                Divider()
                Text("Advanced: Paste token manually")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisclosureGroup("Paste token", isExpanded: $showCodexTokenInput) {
                    VStack(alignment: .leading, spacing: 6) {
                        SecureField("Paste token here...", text: $codexTokenInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))

                        HStack(spacing: 8) {
                            Button("Save Token") {
                                codexProvider?.setManualToken(codexTokenInput)
                                codexTokenInput = ""
                                retryProviderConnection()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(codexTokenInput.isEmpty)

                            if hasManualToken {
                                Button("Clear Token") {
                                    codexProvider?.setManualToken("")
                                    retryProviderConnection()
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func shouldShowClaudeAuthHelp(status: AuthStatus) -> Bool {
        switch status {
        case .needsAuth:
            return true
        case .authenticated:
            guard let error = providerErrorMessage else { return false }
            return isCredentialError(error)
        case .notInstalled:
            return false
        }
    }

    private func claudeAuthHelpMessage(status: AuthStatus) -> String {
        switch status {
        case .needsAuth:
            return "Open Claude Code on your computer (run `claude`) and send a short test prompt. Then click Refresh."
        case .authenticated:
            return "Your Claude token may have expired overnight. Open Claude Code, send a short test prompt to refresh auth, then click Refresh."
        case .notInstalled:
            return ""
        }
    }

    private func shouldShowCodexAuthHelp(status: AuthStatus) -> Bool {
        switch status {
        case .needsAuth:
            return true
        case .authenticated:
            guard let error = providerErrorMessage else { return false }
            return isCredentialError(error)
        case .notInstalled:
            return false
        }
    }

    private func isCredentialError(_ message: String) -> Bool {
        let lower = message.lowercased()
        if lower.contains("401") || lower.contains("unauthorized") {
            return true
        }

        let credentialKeywords = [
            "token", "credential", "authenticate", "authentication", "auth",
            "login", "not configured", "not authenticated", "no access token",
        ]
        let transientKeywords = [
            "timeout", "timed out", "network", "rate limit",
            "server", "decode", "parse", "connection", "temporarily",
        ]

        let hasCredentialSignal = credentialKeywords.contains(where: { lower.contains($0) })
        let hasTransientSignal = transientKeywords.contains(where: { lower.contains($0) })
        return hasCredentialSignal && !hasTransientSignal
    }

    private func retryProviderConnection() {
        let providerId = provider.id
        Task { @MainActor in
            await appState.providerManager.refreshProviderLocalState(for: providerId)
            if let refreshedProvider = appState.providerManager.providers.first(where: { $0.id == providerId }),
               refreshedProvider.isEnabled {
                await appState.providerManager.fetchQuota(for: refreshedProvider)
            }
            appState.ensureMenuBarProviderSelection()
            appState.emitMenuBarPresentationIfNeeded()
        }
    }

    private func refreshAllProviders() {
        Task {
            await appState.manualRefresh()
        }
    }
}
