import SwiftUI

/// Detailed view for a single provider showing per-model breakdown
struct ProviderDetailView: View {
    @ObservedObject var appState: AppState

    private var provider: (any UsageProvider)? {
        appState.selectedProvider
    }

    private var usage: UsageData? {
        guard let id = provider?.id else { return nil }
        return appState.providerManager.usageByProvider[id]
    }

    /// Check if this is the Claude Code local provider
    private var isClaudeCode: Bool {
        provider?.id == "claude-code-local"
    }

    private var claudeProvider: ClaudeCodeProvider? {
        provider as? ClaudeCodeProvider
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button {
                    appState.selectedProvider = nil
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

                if let provider = provider {
                    HStack(spacing: 6) {
                        Image(systemName: provider.iconName)
                            .foregroundStyle(Color(hex: provider.brandColorHex) ?? .blue)
                        Text(provider.name)
                            .font(.headline)
                    }
                }

                Spacer()

                // Balance the back button
                Color.clear.frame(width: 50)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if let usage = usage {
                ScrollView {
                    VStack(spacing: 16) {
                        // Cost summary
                        VStack(spacing: 8) {
                            CostBadgeView(cost: usage.totalCostUSD, size: .large)

                            Text(appState.providerManager.selectedPeriod.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)

                        Divider()
                            .padding(.horizontal)

                        // Token breakdown
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Token Usage")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            TokenCountView(
                                inputTokens: usage.inputTokens,
                                outputTokens: usage.outputTokens,
                                cacheReadTokens: usage.cacheReadTokens,
                                cacheCreationTokens: usage.cacheCreationTokens,
                                compact: false
                            )
                        }
                        .padding(.horizontal, 16)

                        Divider()
                            .padding(.horizontal)

                        // Per-model breakdown
                        if !usage.breakdown.isEmpty {
                            ModelBreakdownView(breakdown: usage.breakdown)
                                .padding(.horizontal, 16)
                        }

                        // Claude Code: Session list
                        if isClaudeCode, let ccProvider = claudeProvider {
                            Divider()
                                .padding(.horizontal)

                            SessionListView(
                                sessions: ccProvider.recentSessions,
                                accountInfo: ccProvider.accountInfo,
                                subscriptionType: ccProvider.subscriptionType
                            )
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                }
            } else {
                VStack {
                    Spacer()
                    ProgressView("Loading...")
                    Spacer()
                }
            }
        }
        .background(.ultraThinMaterial)
    }
}
