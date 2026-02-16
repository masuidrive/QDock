import SwiftUI

/// Shows a list of Claude Code sessions with per-session usage details
struct SessionListView: View {
    let sessions: [ClaudeCodeSession]
    let accountInfo: ClaudeGlobalConfig.OAuthAccount?
    let subscriptionType: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Account info header
            if let account = accountInfo {
                accountHeader(account)
                Divider()
            }

            // Session list
            Text("Sessions (\(sessions.count))")
                .font(.subheadline)
                .fontWeight(.medium)

            if sessions.isEmpty {
                Text("No sessions found for this period")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(sessions) { session in
                    sessionRow(session)
                }
            }
        }
    }

    private func accountHeader(_ account: ClaudeGlobalConfig.OAuthAccount) -> some View {
        HStack(spacing: 10) {
            // Avatar placeholder
            Circle()
                .fill(.blue.opacity(0.15))
                .frame(width: 32, height: 32)
                .overlay {
                    Text(String(account.displayName?.prefix(1) ?? "?"))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }

            VStack(alignment: .leading, spacing: 2) {
                if let name = account.displayName {
                    Text(name)
                        .font(.callout)
                        .fontWeight(.medium)
                }
                if let email = account.emailAddress {
                    Text(email)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let sub = subscriptionType ?? account.subscriptionType {
                Text(sub.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(planColor(sub).opacity(0.15))
                    .foregroundStyle(planColor(sub))
                    .clipShape(Capsule())
            }
        }
    }

    private func sessionRow(_ session: ClaudeCodeSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Project name (last component)
                VStack(alignment: .leading, spacing: 2) {
                    Text(projectName(from: session.projectPath))
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let branch = session.gitBranch {
                            Label(branch, systemImage: "arrow.triangle.branch")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let time = session.startTime {
                            Text(timeFormatted(time))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(session.durationFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(session.messageCount) msgs")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Token bar
            HStack(spacing: 6) {
                tokenPill("In", count: session.totalInputTokens, color: .blue)
                tokenPill("Out", count: session.totalOutputTokens, color: .green)
                if session.totalCacheReadTokens > 0 {
                    tokenPill("Cache", count: session.totalCacheReadTokens, color: .orange)
                }
                Spacer()
                if session.costUSD > 0 {
                    Text(formatCost(session.costUSD))
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
            }

            // Model tags
            if !session.models.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(session.models).sorted(), id: \.self) { model in
                        Text(shortModelName(model))
                            .font(.system(size: 9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.primary.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.primary.opacity(0.05), lineWidth: 1)
                )
        )
    }

    // MARK: - Helpers

    private func projectName(from path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private func timeFormatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func tokenPill(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color.opacity(0.7)).frame(width: 5, height: 5)
            Text("\(formatTokens(count))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private func formatCost(_ cost: Double) -> String {
        String(format: "$%.2f", cost)
    }

    private func shortModelName(_ name: String) -> String {
        name.replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20250514", with: "")
            .replacingOccurrences(of: "-20250929", with: "")
            .replacingOccurrences(of: "-20251001", with: "")
    }

    private func planColor(_ plan: String) -> Color {
        switch plan.lowercased() {
        case "max": return .purple
        case "pro": return .blue
        case "team": return .orange
        case "enterprise": return .red
        default: return .gray
        }
    }
}
