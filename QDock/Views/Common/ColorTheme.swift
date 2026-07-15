import SwiftUI
import AppKit

// MARK: - AppearanceMode

/// User-selectable appearance for the popover UI.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case dark
    case light
    case glass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .dark: return "Dark"
        case .light: return "Light"
        case .glass: return "Glass"
        }
    }

    /// nil follows the system appearance.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system, .glass: return nil
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        }
    }

    /// Glass keeps the popover's native translucent material
    /// (Liquid Glass on macOS 26+) instead of the flat notebook panel.
    var isGlass: Bool { self == .glass }
}

// MARK: - NotebookPalette

/// Theme-resolved colors for the notebook UI. Dark is the ink panel from
/// the site's product previews; light is the site's cream-paper canvas.
struct NotebookPalette {
    let isDark: Bool
    let panel: Color        // popover surface
    let lifted: Color       // footer strip, settings cards
    let hairline: Color     // separators, card borders
    let title: Color        // "Usage", section headings
    let label: Color        // row labels
    let section: Color      // provider names
    let meta: Color         // mono metadata (updated / resets / cadence)

    var barTrack: Color { hairline }

    /// Bar fill for a usage percent (accent hue, tuned per theme).
    func usageBar(_ percent: Double) -> Color {
        isDark ? ColorTheme.usageAccentDark(percent) : ColorTheme.usageBarLight(percent)
    }

    /// Text color for a usage percent (kept readable against the panel).
    func usageText(_ percent: Double) -> Color {
        isDark ? ColorTheme.usageAccentDark(percent) : ColorTheme.usageTextLight(percent)
    }
}

// MARK: - ColorTheme

/// Centralized color system matching the qdock.saidaltan.com
/// "engineering notebook" design language.
enum ColorTheme {
    // MARK: Dark accents (site palette, straight from DESIGN.md)

    static let usageGreen = Color(red: 0.482, green: 0.847, blue: 0.561)   // #7BD88F mint
    static let usageYellow = Color(red: 0.973, green: 0.902, blue: 0.478)  // #F8E67A canary
    static let usageOrange = Color(red: 0.871, green: 0.365, blue: 0.200)  // #DE5D33 ember
    static let usageRed = Color(red: 0.988, green: 0.380, blue: 0.553)     // #FC618D hot pink

    // MARK: Neutrals

    static let ink = Color(red: 0.078, green: 0.078, blue: 0.078)          // #141414
    static let charcoal = Color(red: 0.161, green: 0.161, blue: 0.161)     // #292929
    static let graphite = Color(red: 0.220, green: 0.220, blue: 0.227)     // #38383A
    static let mist = Color(red: 0.898, green: 0.898, blue: 0.898)         // #E5E5E5
    static let ash = Color(red: 0.663, green: 0.663, blue: 0.675)          // #A9A9AC
    static let fog = Color(red: 0.427, green: 0.427, blue: 0.439)          // #6D6D70
    static let cream = Color(red: 0.965, green: 0.965, blue: 0.965)        // #F6F6F6

    // MARK: Brand

    static let claudeAccent = Color(red: 0.831, green: 0.647, blue: 0.455) // #D4A574

    // MARK: Palettes

    static let darkPalette = NotebookPalette(
        isDark: true,
        panel: ink,
        lifted: Color(red: 0.106, green: 0.106, blue: 0.106),              // #1B1B1B
        hairline: graphite,
        title: .white,
        label: mist,
        section: ash,
        meta: Color(red: 0.596, green: 0.596, blue: 0.616)                 // #98989D
    )

    static let lightPalette = NotebookPalette(
        isDark: false,
        panel: .white,
        lifted: cream,
        hairline: mist,
        title: ink,
        label: ink,
        section: fog,
        meta: fog
    )

    static func palette(for colorScheme: ColorScheme) -> NotebookPalette {
        colorScheme == .dark ? darkPalette : lightPalette
    }

    // MARK: Usage color scales

    static func usageAccentDark(_ percent: Double) -> Color {
        switch percent {
        case ..<50: return usageGreen
        case 50..<75: return usageYellow
        case 75..<90: return usageOrange
        default: return usageRed
        }
    }

    /// Bar fills on light surfaces: same hues, deepened enough to read
    /// against a white panel and mist track.
    static func usageBarLight(_ percent: Double) -> Color {
        switch percent {
        case ..<50: return Color(red: 0.247, green: 0.627, blue: 0.365)    // #3FA05D
        case 50..<75: return Color(red: 0.851, green: 0.702, blue: 0.180)  // #D9B32E
        case 75..<90: return Color(red: 0.871, green: 0.365, blue: 0.200)  // #DE5D33
        default: return Color(red: 0.910, green: 0.267, blue: 0.478)       // #E8447A
        }
    }

    /// Percent text on light surfaces: value-shifted further for contrast.
    static func usageTextLight(_ percent: Double) -> Color {
        switch percent {
        case ..<50: return Color(red: 0.180, green: 0.486, blue: 0.275)    // #2E7C46
        case 50..<75: return Color(red: 0.561, green: 0.443, blue: 0.110)  // #8F711C
        case 75..<90: return Color(red: 0.702, green: 0.267, blue: 0.118)  // #B3441E
        default: return Color(red: 0.769, green: 0.157, blue: 0.345)       // #C42858
        }
    }

    static func colorForUsage(_ percent: Double) -> Color {
        usageAccentDark(percent)
    }

    /// Menu bar ring/text color: dynamic so it stays legible on both
    /// dark and light menu bars.
    static func nsColorForUsage(_ percent: Double) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? nsUsageDark(percent) : nsUsageLight(percent)
        }
    }

    private static func nsUsageDark(_ percent: Double) -> NSColor {
        switch percent {
        case ..<50: return NSColor(red: 0.482, green: 0.847, blue: 0.561, alpha: 1)
        case 50..<75: return NSColor(red: 0.973, green: 0.902, blue: 0.478, alpha: 1)
        case 75..<90: return NSColor(red: 0.871, green: 0.365, blue: 0.200, alpha: 1)
        default: return NSColor(red: 0.988, green: 0.380, blue: 0.553, alpha: 1)
        }
    }

    private static func nsUsageLight(_ percent: Double) -> NSColor {
        switch percent {
        case ..<50: return NSColor(red: 0.180, green: 0.486, blue: 0.275, alpha: 1)
        case 50..<75: return NSColor(red: 0.561, green: 0.443, blue: 0.110, alpha: 1)
        case 75..<90: return NSColor(red: 0.702, green: 0.267, blue: 0.118, alpha: 1)
        default: return NSColor(red: 0.769, green: 0.157, blue: 0.345, alpha: 1)
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
