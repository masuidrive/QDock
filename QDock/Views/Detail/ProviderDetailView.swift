import SwiftUI

/// Detailed view for a single provider showing quota windows
@MainActor
struct ProviderDetailView: View {
    let appState: AppState

    private var provider: (any QuotaProvider)? {
        appState.selectedProvider
    }

    private var quota: QuotaData? {
        guard let id = provider?.id else { return nil }
        return appState.providerManager.quotaByProvider[id]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            headerView

            Divider()

            if let quota = quota {
                ScrollView {
                    VStack(spacing: 20) {
                        // Hero ring
                        heroRing(quota: quota)
                            .padding(.top, 16)

                        // Plan badge
                        if let plan = quota.planName {
                            planBadge(plan: plan)
                        }

                        // Account section
                        if let email = quota.accountEmail ?? (provider as? ClaudeCodeProvider)?.accountEmail {
                            accountCard(email: email, plan: quota.planName)
                        }

                        // Window cards (exclude session if hero already shows it)
                        ForEach(quota.windowsExcludingSessionWhenAvailable) { window in
                            UsageCardView(window: window, barHeight: 10)
                        }

                        // Auth status
                        authStatusCard

                        // Stale indicator
                        if quota.isStale {
                            staleIndicator
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            } else if let error = appState.providerManager.errorsByProvider[provider?.id ?? ""] {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Spacer()
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

    // MARK: - Header

    private var headerView: some View {
        Group {
            if let provider = provider {
                HStack(spacing: 6) {
                    Image(systemName: provider.iconName)
                        .foregroundStyle(Color(hex: provider.brandColorHex) ?? .blue)
                    Text(provider.name)
                        .font(.headline)
                }
            } else {
                Text("Details")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
            Button {
                appState.selectedProvider = nil
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

    // MARK: - Hero Ring

    private func heroRing(quota: QuotaData) -> some View {
        let heroWindow = quota.sessionWindow ?? quota.primaryWindow
        let heroPercent = heroWindow?.usagePercent ?? 0
        let isCritical = heroPercent >= 90

        return VStack(spacing: 10) {
            ZStack {
                ProgressRingView(
                    progress: heroPercent,
                    size: 120,
                    lineWidth: 14
                )
                .if(isCritical) { view in
                    view.glowEffect(color: ColorTheme.colorForUsage(heroPercent))
                }

                VStack(spacing: 2) {
                    AnimatedPercentage(percent: heroPercent, fontSize: 32)

                    if let plan = quota.planName {
                        Text(plan)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let countdown = heroWindow?.resetCountdown {
                Text("Resets in \(countdown)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Plan Badge

    private func planBadge(plan: String) -> some View {
        Text(plan)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.claudeAccent, .claudeAccent.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: .claudeAccent.opacity(0.3), radius: 4, y: 2)
            )
    }

    // MARK: - Account Card

    private func accountCard(email: String, plan: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text(email)
                    .font(.callout)
                    .foregroundStyle(.primary)
            }

            if let plan = plan {
                HStack(spacing: 8) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.claudeAccent)
                    Text("\(plan) plan")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Auth Status

    @ViewBuilder
    private var authStatusCard: some View {
        if let provider = provider {
            let status = provider.authStatus

            HStack(spacing: 8) {
                Image(systemName: status.isAuthenticated ? "checkmark.seal.fill" : "exclamationmark.triangle")
                    .foregroundStyle(status.isAuthenticated ? .green : .orange)
                    .font(.system(size: 14))
                Text(status.isAuthenticated ? "Authenticated" : status.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if status.isAuthenticated {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.usageGreen)
                        .font(.caption)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                    )
            )
        }
    }

    // MARK: - Stale Indicator

    private var staleIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text("Showing cached data — unable to reach server")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.orange.opacity(0.08))
        )
    }
}
