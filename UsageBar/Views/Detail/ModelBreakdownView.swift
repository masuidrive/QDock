import SwiftUI

/// Table showing per-model usage breakdown
struct ModelBreakdownView: View {
    let breakdown: [UsageBreakdown]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model Breakdown")
                .font(.subheadline)
                .fontWeight(.medium)

            ForEach(breakdown) { model in
                modelRow(model)
            }
        }
    }

    private func modelRow(_ model: UsageBreakdown) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(cleanModelName(model.model))
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                if model.costUSD > 0 {
                    CostBadgeView(cost: model.costUSD, size: .small)
                }
            }

            // Token bar
            GeometryReader { geometry in
                let total = max(model.totalTokens, 1)
                let inputWidth = CGFloat(model.inputTokens) / CGFloat(total) * geometry.size.width
                let outputWidth = CGFloat(model.outputTokens) / CGFloat(total) * geometry.size.width
                let cacheWidth = CGFloat(model.cacheReadTokens) / CGFloat(total) * geometry.size.width

                HStack(spacing: 1) {
                    if model.inputTokens > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.blue.opacity(0.7))
                            .frame(width: max(inputWidth, 2), height: 6)
                    }
                    if model.outputTokens > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.green.opacity(0.7))
                            .frame(width: max(outputWidth, 2), height: 6)
                    }
                    if model.cacheReadTokens > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.orange.opacity(0.7))
                            .frame(width: max(cacheWidth, 2), height: 6)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 6)

            HStack {
                Text(formatTokens(model.totalTokens) + " tokens")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.primary.opacity(0.03))
        )
    }

    private func cleanModelName(_ name: String) -> String {
        // Clean up model names for display
        name.replacingOccurrences(of: "claude-", with: "Claude ")
            .replacingOccurrences(of: "gpt-", with: "GPT-")
            .replacingOccurrences(of: "-20250", with: " (")
            .appending(name.contains("-2025") ? ")" : "")
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
