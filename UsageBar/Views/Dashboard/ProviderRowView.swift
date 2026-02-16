import SwiftUI

/// A single provider row in the dashboard
struct ProviderRowView: View {
    let provider: any UsageProvider
    let usage: UsageData?
    let error: String?
    let isLoading: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Provider icon
                Image(systemName: provider.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: provider.brandColorHex) ?? .blue)
                    .frame(width: 28, height: 28)

                // Provider info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(provider.name)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        if provider.id == "claude-code-local" {
                            Text("LOCAL")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }

                    if isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    } else if let error = error {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    } else if let usage = usage {
                        TokenCountView(
                            inputTokens: usage.inputTokens,
                            outputTokens: usage.outputTokens,
                            cacheReadTokens: usage.cacheReadTokens
                        )
                    } else {
                        Text("No data")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // Cost
                if let usage = usage {
                    CostBadgeView(cost: usage.totalCostUSD, size: .medium)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.primary.opacity(0.03))
                .padding(.horizontal, 8)
        )
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
