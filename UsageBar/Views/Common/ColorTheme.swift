import SwiftUI
import AppKit

/// Centralized color system for usage visualization
enum ColorTheme {
    // MARK: - Usage Colors

    static let usageGreen = Color(red: 0.204, green: 0.780, blue: 0.349)   // #34C759
    static let usageYellow = Color(red: 1.0, green: 0.800, blue: 0.0)      // #FFCC00
    static let usageOrange = Color(red: 0.902, green: 0.494, blue: 0.0)    // #E67E00
    static let usageRed = Color(red: 1.0, green: 0.231, blue: 0.188)       // #FF3B30

    // MARK: - Brand

    static let claudeAccent = Color(red: 0.831, green: 0.647, blue: 0.455) // #D4A574

    // MARK: - Glass

    static let glassOverlay = Color.white.opacity(0.05)
    static let glassBorder = Color.white.opacity(0.1)

    // MARK: - Methods

    static func colorForUsage(_ percent: Double) -> Color {
        switch percent {
        case ..<50: return usageGreen
        case 50..<75: return usageYellow
        case 75..<90: return usageOrange
        default: return usageRed
        }
    }

    static func gradientForUsage(_ percent: Double) -> LinearGradient {
        let base = colorForUsage(percent)
        return LinearGradient(
            colors: [base.opacity(0.8), base],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func nsColorForUsage(_ percent: Double) -> NSColor {
        switch percent {
        case ..<50: return NSColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1)
        case 50..<75: return NSColor(red: 1.0, green: 0.800, blue: 0.0, alpha: 1)
        case 75..<90: return NSColor(red: 0.902, green: 0.494, blue: 0.0, alpha: 1)
        default: return NSColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1)
        }
    }
}

// MARK: - Color Extensions

extension Color {
    static let usageGreen = ColorTheme.usageGreen
    static let usageYellow = ColorTheme.usageYellow
    static let usageOrange = ColorTheme.usageOrange
    static let usageRed = ColorTheme.usageRed
    static let claudeAccent = ColorTheme.claudeAccent

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
