import Foundation

// MARK: - QuotaWindow

/// A single usage quota window (e.g., 5-hour session, 7-day weekly,
/// or a model-scoped weekly limit like Fable)
struct QuotaWindow: Identifiable, Equatable, Codable {
    let id: String                      // "session", "weekly", "weekly-fable"
    let displayName: String             // "Session (5h)", "Weekly", "Fable Weekly"
    let usagePercent: Double            // 0.0 - 100.0
    let resetsAt: Date?                 // When the window resets
    let windowDurationMinutes: Int?     // Duration of the window in minutes
    let severity: String?               // Server-reported severity, when available
    let isActive: Bool?                 // Server-reported "currently binding" flag

    init(
        id: String,
        displayName: String,
        usagePercent: Double,
        resetsAt: Date?,
        windowDurationMinutes: Int?,
        severity: String? = nil,
        isActive: Bool? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.usagePercent = usagePercent
        self.resetsAt = resetsAt
        self.windowDurationMinutes = windowDurationMinutes
        self.severity = severity
        self.isActive = isActive
    }

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

    /// Percentage of the quota window that has elapsed at a given time.
    /// Returns nil when the provider does not expose enough timing data.
    func timeProgressPercent(at date: Date = Date()) -> Double? {
        guard let resetsAt,
              let windowDurationMinutes,
              windowDurationMinutes > 0 else {
            return nil
        }

        let duration = TimeInterval(windowDurationMinutes) * 60
        let windowStart = resetsAt.addingTimeInterval(-duration)
        let elapsed = date.timeIntervalSince(windowStart)
        return max(0, min(elapsed / duration * 100, 100))
    }

    /// Usage level for color coding (server severity can only escalate)
    var level: UsageLevel {
        UsageLevel.from(percent: usagePercent, severity: severity)
    }
}

// MARK: - UsageCreditsInfo

/// "Usage credits" (formerly "extra usage") state for providers that
/// support paid overage on top of plan limits.
struct UsageCreditsInfo: Equatable, Codable {
    let usedCredits: Double?
    let monthlyLimit: Double?
    let utilization: Double?            // 0.0 - 100.0
    let currency: String?
}

// MARK: - QuotaData

/// All quota data for a single provider
struct QuotaData: Identifiable, Equatable, Codable {
    let id: String                      // matches provider id
    let provider: String                // display name
    let planName: String?               // "Pro", "Max 5x", "Plus"
    let windows: [QuotaWindow]          // session + weekly + model-scoped
    let accountEmail: String?
    let fetchedAt: Date
    let isStale: Bool                   // true if from cache (offline)
    let usageCredits: UsageCreditsInfo? // paid overage state, when enabled

    init(
        id: String,
        provider: String,
        planName: String?,
        windows: [QuotaWindow],
        accountEmail: String?,
        fetchedAt: Date,
        isStale: Bool,
        usageCredits: UsageCreditsInfo? = nil
    ) {
        self.id = id
        self.provider = provider
        self.planName = planName
        self.windows = windows
        self.accountEmail = accountEmail
        self.fetchedAt = fetchedAt
        self.isStale = isStale
        self.usageCredits = usageCredits
    }

    /// The highest usage percent across all windows
    var maxUsagePercent: Double {
        windows.map(\.usagePercent).max() ?? 0
    }

    /// The window with the highest usage
    var primaryWindow: QuotaWindow? {
        windows.max(by: { $0.usagePercent < $1.usagePercent })
    }

    /// The session window (5-hour-ish).
    ///
    /// Some providers may mislabel primary/secondary windows, so we prefer
    /// a short-duration window (<= 12h) when available.
    var sessionWindow: QuotaWindow? {
        let sessionIds = Set(["session", "five_hour"])
        let shortWindowUpperBoundMinutes = 12 * 60

        if let explicitSession = windows.first(where: {
            guard sessionIds.contains($0.id) else { return false }
            if let duration = $0.windowDurationMinutes {
                return duration > 0 && duration <= shortWindowUpperBoundMinutes
            }
            return true
        }) {
            return explicitSession
        }

        if let shortestShortWindow = windows
            .filter({
                guard let duration = $0.windowDurationMinutes else { return false }
                return duration > 0 && duration <= shortWindowUpperBoundMinutes
            })
            .min(by: {
                ($0.windowDurationMinutes ?? Int.max) < ($1.windowDurationMinutes ?? Int.max)
            }) {
            return shortestShortWindow
        }

        return windows.first { sessionIds.contains($0.id) }
    }

    /// Session usage percent (menu bar source of truth)
    var sessionUsagePercent: Double {
        sessionWindow?.usagePercent ?? 0
    }

    /// Window list excluding the session window when one exists.
    ///
    /// Used by expanded views to avoid rendering session twice
    /// (hero ring + duplicated session card).
    var windowsExcludingSessionWhenAvailable: [QuotaWindow] {
        guard let session = sessionWindow else { return windows }
        return windows.filter { $0 != session }
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

    /// Combine the percent-derived level with a server-reported severity.
    /// The server signal can only escalate, never downgrade, so an unknown
    /// vocabulary value degrades gracefully to the percent-based level.
    static func from(percent: Double, severity: String?) -> UsageLevel {
        let base = from(percent: percent)
        switch severity?.lowercased() {
        case "warning", "elevated", "high":
            return base == .critical ? .critical : .high
        case "critical", "exceeded", "limited", "rate_limited":
            return .critical
        default:
            return base
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
