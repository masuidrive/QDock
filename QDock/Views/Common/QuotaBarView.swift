import SwiftUI

/// Reusable progress bar showing quota usage with label, percent, and color coding
struct QuotaBarView: View {
    let label: String
    let percent: Double
    let resetCountdown: String?
    let height: CGFloat

    @State private var displayedProgress: Double = 0

    init(label: String, percent: Double, resetCountdown: String? = nil, height: CGFloat = 8) {
        self.label = label
        self.percent = percent
        self.resetCountdown = resetCountdown
        self.height = height
    }

    private var barColor: Color {
        ColorTheme.colorForUsage(percent)
    }

    private var progressFraction: CGFloat {
        CGFloat(max(0, min(displayedProgress, 100)) / 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !label.isEmpty {
                HStack {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    AnimatedPercentage(percent: percent, fontSize: 11)

                    if let countdown = resetCountdown {
                        Text(countdown)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Progress bar
            RoundedRectangle(cornerRadius: height / 2)
                .fill(Color.primary.opacity(0.08))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(barColor)
                        .scaleEffect(x: progressFraction, y: 1, anchor: .leading)
                }
            .frame(height: height)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5)) {
                displayedProgress = percent
            }
        }
        .onChange(of: percent) { _, newValue in
            withAnimation(.easeInOut(duration: 0.3)) {
                displayedProgress = newValue
            }
        }
    }
}

