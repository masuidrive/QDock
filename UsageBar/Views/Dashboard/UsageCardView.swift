import SwiftUI

/// Glass card for a quota window (session, weekly, sonnet limit)
struct UsageCardView: View {
    let window: QuotaWindow
    let barHeight: CGFloat

    init(window: QuotaWindow, barHeight: CGFloat = 6) {
        self.window = window
        self.barHeight = barHeight
    }

    private var progressColor: Color {
        ColorTheme.colorForUsage(window.usagePercent)
    }

    private var isCritical: Bool {
        window.usagePercent >= 90
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: title + percentage
            HStack {
                Text(window.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let duration = window.windowDurationMinutes {
                    let hours = duration / 60
                    Text(hours > 24 ? "(\(hours / 24)d)" : "(\(hours)h)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                AnimatedPercentage(percent: window.usagePercent, fontSize: 16)
            }

            // Content: ring + bar + reset
            HStack(spacing: 14) {
                ProgressRingView(
                    progress: window.usagePercent,
                    size: 50,
                    lineWidth: 6
                )

                VStack(alignment: .leading, spacing: 8) {
                    // Progress bar
                    QuotaBarView(
                        label: "",
                        percent: window.usagePercent,
                        height: barHeight
                    )

                    // Reset countdown
                    if let countdown = window.resetCountdown {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text("Resets: \(countdown)")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
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
        .shadow(
            color: isCritical ? progressColor.opacity(0.3) : .clear,
            radius: isCritical ? 8 : 0
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.displayName), \(Int(window.usagePercent)) percent used")
    }
}
