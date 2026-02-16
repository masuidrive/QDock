import SwiftUI

/// Summary header showing total cost and tokens across all providers
struct UsageSummaryView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(appState.providerManager.selectedPeriod.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                CostBadgeView(
                    cost: appState.providerManager.totalCost,
                    size: .large
                )
            }

            // Token summary bar
            HStack(spacing: 16) {
                tokenStat(
                    "Total Tokens",
                    value: appState.formatTokens(appState.providerManager.totalTokens)
                )

                Spacer()

                tokenStat(
                    "Providers",
                    value: "\(appState.providerManager.activeProviders.count)"
                )
            }
        }
        .padding(.horizontal, 16)
    }

    private func tokenStat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.callout)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }
}
