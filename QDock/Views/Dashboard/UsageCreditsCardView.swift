import SwiftUI

/// Glass card for paid "usage credits" (formerly "extra usage") state.
/// Shown only when the provider reports the feature as enabled.
struct UsageCreditsCardView: View {
    let credits: UsageCreditsInfo

    private var utilization: Double? {
        credits.utilization
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "creditcard")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Usage Credits")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                if let utilization {
                    AnimatedPercentage(percent: utilization, fontSize: 16)
                }
            }

            if let utilization {
                QuotaBarView(label: "", percent: utilization, height: 6)
            }

            if let used = credits.usedCredits {
                HStack(spacing: 4) {
                    Text(creditsLine(used: used, limit: credits.monthlyLimit))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if utilization == nil {
                Text("Enabled — no usage this month")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Usage credits\(utilization.map { ", \(Int($0)) percent used" } ?? "")")
    }

    private func creditsLine(used: Double, limit: Double?) -> String {
        let usedText = Self.formatAmount(used)
        if let limit {
            return "\(usedText) of \(Self.formatAmount(limit)) monthly credits used"
        }
        return "\(usedText) credits used this month"
    }

    private static func formatAmount(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }
}
