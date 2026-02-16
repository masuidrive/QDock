import SwiftUI

/// Displays token counts with input/output/cache breakdown
struct TokenCountView: View {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let compact: Bool

    init(
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        compact: Bool = true
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.compact = compact
    }

    var body: some View {
        if compact {
            HStack(spacing: 8) {
                tokenLabel("In", count: inputTokens, color: .blue)
                tokenLabel("Out", count: outputTokens, color: .green)
                if cacheReadTokens > 0 {
                    tokenLabel("Cache", count: cacheReadTokens, color: .orange)
                }
            }
            .font(.caption)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                tokenRow("Input Tokens", count: inputTokens, color: .blue)
                tokenRow("Output Tokens", count: outputTokens, color: .green)
                if cacheReadTokens > 0 {
                    tokenRow("Cache Read", count: cacheReadTokens, color: .orange)
                }
                if cacheCreationTokens > 0 {
                    tokenRow("Cache Creation", count: cacheCreationTokens, color: .purple)
                }
            }
        }
    }

    private func tokenLabel(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            Circle()
                .fill(color.opacity(0.8))
                .frame(width: 6, height: 6)
            Text("\(formatTokens(count)) \(label.lowercased())")
                .foregroundStyle(.secondary)
        }
    }

    private func tokenRow(_ label: String, count: Int, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color.opacity(0.8))
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatTokens(count))
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.callout)
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
