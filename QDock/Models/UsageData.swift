import Foundation

// MARK: - QuotaWindow

/// A single usage quota window (e.g., 5-hour session or 7-day weekly)
struct QuotaWindow: Identifiable, Equatable {
    let id: String                      // "session", "weekly"
    let displayName: String             // "Session (5h)", "Weekly"
    let usagePercent: Double            // 0.0 - 100.0
    let resetsAt: Date?                 // When the window resets
    let windowDurationMinutes: Int?     // Duration of the window in minutes

    /// Time remaining until reset
    var timeUntilReset: TimeInterval? {
        guard let resetsAt = resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    /// Formatted countdown string (e.g., "2h 47m" or "3d 4h")
    var resetCountdown: String? {
        guard let remaining = timeUntilReset else { return nil }
        let totalMinutes = Int(remaining) / 60
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Usage level for color coding
    var level: UsageLevel {
        UsageLevel.from(percent: usagePercent)
    }
}

// MARK: - QuotaData

/// All quota data for a single provider
struct QuotaData: Identifiable, Equatable {
    let id: String                      // matches provider id
    let provider: String                // display name
    let planName: String?               // "Pro", "Max 5x", "Plus"
    let windows: [QuotaWindow]          // session + weekly
    let accountEmail: String?
    let fetchedAt: Date
    let isStale: Bool                   // true if from cache (offline)

    /// The highest usage percent across all windows
    var maxUsagePercent: Double {
        windows.map(\.usagePercent).max() ?? 0
    }

    /// The window with the highest usage
    var primaryWindow: QuotaWindow? {
        windows.max(by: { $0.usagePercent < $1.usagePercent })
    }

    /// The session window (5-hour)
    var sessionWindow: QuotaWindow? {
        windows.first { $0.id == "session" || $0.id == "five_hour" }
    }

    /// The weekly window (7-day)
    var weeklyWindow: QuotaWindow? {
        windows.first { $0.id == "weekly" || $0.id == "seven_day" }
    }

    /// Earliest reset time across all windows
    var earliestReset: Date? {
        windows.compactMap(\.resetsAt).min()
    }

    /// Usage level based on the highest window
    var level: UsageLevel {
        UsageLevel.from(percent: maxUsagePercent)
    }

    static func == (lhs: QuotaData, rhs: QuotaData) -> Bool {
        lhs.id == rhs.id && lhs.fetchedAt == rhs.fetchedAt
    }

    static var empty: QuotaData {
        QuotaData(
            id: "",
            provider: "",
            planName: nil,
            windows: [],
            accountEmail: nil,
            fetchedAt: Date(),
            isStale: false
        )
    }
}

// MARK: - UsageLevel

/// Color-coded usage severity levels
enum UsageLevel {
    case low        // 0-50%   green
    case moderate   // 50-75%  yellow
    case high       // 75-90%  orange
    case critical   // 90%+    red

    static func from(percent: Double) -> UsageLevel {
        switch percent {
        case 0..<50: return .low
        case 50..<75: return .moderate
        case 75..<90: return .high
        default: return .critical
        }
    }

    var colorName: String {
        switch self {
        case .low: return "green"
        case .moderate: return "yellow"
        case .high: return "orange"
        case .critical: return "red"
        }
    }
}
