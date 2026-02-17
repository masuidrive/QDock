import SwiftUI

/// Circular progress ring with color-coded fill
struct ProgressRingView: View {
    let progress: Double // 0.0 - 100.0
    let size: CGFloat
    let lineWidth: CGFloat

    init(progress: Double, size: CGFloat = 80, lineWidth: CGFloat = 8) {
        self.progress = progress
        self.size = size
        self.lineWidth = lineWidth
    }

    private var progressColor: Color {
        ColorTheme.colorForUsage(progress)
    }

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(progressColor.opacity(0.12), lineWidth: lineWidth)
                .frame(width: size, height: size)

            // Progress arc
            Circle()
                .trim(from: 0, to: min(progress / 100, 1.0))
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.6), value: progress)
        }
    }
}
