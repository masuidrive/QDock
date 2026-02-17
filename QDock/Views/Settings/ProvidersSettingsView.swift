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

                authStatusBadge

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
                claudeCodeStatusView
            case "codex":
                codexStatusView
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
    private var authStatusBadge: some View {
        let status = provider.authStatus

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

    @State private var tokenInput: String = ""
    @State private var showTokenInput: Bool = false

    @ViewBuilder
    private var claudeCodeStatusView: some View {
        let ccProvider = provider as? ClaudeCodeProvider

        VStack(alignment: .leading, spacing: 8) {
            // Detection status
            if let result = ccProvider?.detectionResult {
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

            // Auth status
            HStack(spacing: 6) {
                Image(systemName: ccProvider?.isLoggedIn == true ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(ccProvider?.isLoggedIn == true ? Color.usageGreen : Color.usageOrange)
                    .font(.caption)
                Text(ccProvider?.isLoggedIn == true ? "Authenticated" : "Not authenticated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Account info
            if let email = ccProvider?.accountEmail {
                HStack(spacing: 6) {
                    Image(systemName: "person.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Subscription
            if let plan = ccProvider?.planDisplayName {
                HStack(spacing: 6) {
                    Image(systemName: "star.circle")
                        .font(.caption)
                        .foregroundStyle(Color.claudeAccent)
                    Text("\(plan) plan")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Onboarding: manual token entry if not authenticated
            if ccProvider?.isLoggedIn != true {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("To authenticate, either:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Text("A.")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                        Text("Run `claude` in your terminal to log in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        Text("B.")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                        Text("Paste token from: `security find-generic-password -s 'Claude Code-credentials' -w`")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    DisclosureGroup("Paste token", isExpanded: $showTokenInput) {
                        VStack(alignment: .leading, spacing: 6) {
                            SecureField("Paste token here...", text: $tokenInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))

                            Button("Save Token") {
                                ccProvider?.setManualToken(tokenInput)
                                tokenInput = ""
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
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(tokenInput.isEmpty)
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Codex Status

    @ViewBuilder
    private var codexStatusView: some View {
        let isInstalled = provider.isConfigured

        VStack(alignment: .leading, spacing: 6) {
            // Installation status
            HStack(spacing: 6) {
                Image(systemName: isInstalled ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(isInstalled ? Color.usageGreen : Color.usageOrange)
                    .font(.caption)
                Text(isInstalled ? "Codex installed" : "Codex not found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isInstalled {
                Text("Codex uses its own authentication — no extra setup needed.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Install Codex: npm i -g @openai/codex")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

}
