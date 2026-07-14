import SwiftUI

/// Animated percentage with color coding and SF Pro Rounded
struct AnimatedPercentage: View {
    let percent: Double
    let fontSize: CGFloat

    init(percent: Double, fontSize: CGFloat = 14) {
        self.percent = percent
        self.fontSize = fontSize
    }

    var body: some View {
        Text("\(Int(percent))%")
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(ColorTheme.colorForUsage(percent))
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.3), value: Int(percent))
    }
}

// MARK: - Glow Effect

struct GlowEffect: ViewModifier {
    let color: Color
    @State private var isGlowing = false

    func body(content: Content) -> some View {
        content
            .shadow(
                color: color.opacity(isGlowing ? 0.8 : 0.3),
                radius: isGlowing ? 10 : 5
            )
            .animation(
                .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                value: isGlowing
            )
            .onAppear { isGlowing = true }
    }
}

// MARK: - View Extensions

extension View {
    func glowEffect(color: Color = .usageRed) -> some View {
        modifier(GlowEffect(color: color))
    }
}
