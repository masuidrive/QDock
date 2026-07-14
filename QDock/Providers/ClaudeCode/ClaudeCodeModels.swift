import Foundation

// MARK: - Claude Usage API Response

/// Response from GET https://api.anthropic.com/api/oauth/usage
///
/// NOTE: No explicit CodingKeys here — NetworkClient uses
/// `keyDecodingStrategy = .convertFromSnakeCase` which automatically
/// maps `five_hour` → `fiveHour`, `resets_at` → `resetsAt`, etc.
/// Adding manual CodingKeys would double-convert and break decoding.
struct ClaudeUsageResponse: Decodable {
    // Legacy flat windows. Anthropic moved per-model weekly windows into
    // `limits[]` during 2026; the flat `seven_day_<model>` keys now come
    // back null and are kept only as a fallback for older responses.
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?

    /// Modern generic representation: session, weekly-all, and
    /// model-scoped weekly windows (e.g. Fable), each with severity.
    let limits: [Limit]?

    /// "Usage credits" (formerly "extra usage") paid-overage state.
    let extraUsage: ExtraUsage?

    struct UsageWindow: Decodable {
        let utilization: Double?        // 0.0 - 100.0
        let resetsAt: Date?             // ISO8601 date (decoded by .iso8601 strategy)
    }

    struct Limit: Decodable {
        let kind: String?               // "session", "weekly_all", "weekly_scoped"
        let group: String?              // "session", "weekly"
        let percent: Double?            // NOTE: limits[] uses `percent`, not `utilization`
        let severity: String?           // "normal", ...
        let resetsAt: Date?
        let scope: Scope?
        let isActive: Bool?

        struct Scope: Decodable {
            let model: Model?

            struct Model: Decodable {
                let id: String?
                let displayName: String?
            }
        }
    }

    struct ExtraUsage: Decodable {
        let isEnabled: Bool?
        let monthlyLimit: Double?
        let usedCredits: Double?
        let utilization: Double?        // 0.0 - 100.0
        let currency: String?
    }

    /// Convert to QuotaData
    func toQuotaData(provider: String, planName: String?, email: String?) -> QuotaData {
        var windows = windowsFromLimits()
        if windows.isEmpty {
            windows = windowsFromLegacyFields()
        }

        var credits: UsageCreditsInfo?
        if let extra = extraUsage, extra.isEnabled == true {
            credits = UsageCreditsInfo(
                usedCredits: extra.usedCredits,
                monthlyLimit: extra.monthlyLimit,
                utilization: extra.utilization,
                currency: extra.currency
            )
        }

        return QuotaData(
            id: "claude-code",
            provider: provider,
            planName: planName,
            windows: windows,
            accountEmail: email,
            fetchedAt: Date(),
            isStale: false,
            usageCredits: credits
        )
    }

    /// Build windows from the modern `limits[]` array (preferred source).
    private func windowsFromLimits() -> [QuotaWindow] {
        guard let limits, !limits.isEmpty else { return [] }

        return limits.compactMap { limit -> QuotaWindow? in
            guard let kind = limit.kind else { return nil }

            let isWeekly = limit.group == "weekly" || kind.hasPrefix("weekly")
            let duration = isWeekly ? 10080 : (kind == "session" ? 300 : nil)

            let id: String
            let displayName: String
            switch kind {
            case "session":
                id = "session"
                displayName = "Session (5h)"
            case "weekly_all":
                id = "weekly"
                displayName = "Weekly (All Models)"
            case "weekly_scoped":
                let modelName = limit.scope?.model?.displayName ?? "Model"
                id = "weekly-\(modelName.lowercased().replacingOccurrences(of: " ", with: "-"))"
                displayName = "\(modelName) Weekly"
            default:
                // Unknown future kinds: surface them instead of dropping data.
                id = kind
                displayName = kind
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized
            }

            return QuotaWindow(
                id: id,
                displayName: displayName,
                usagePercent: limit.percent ?? 0,
                resetsAt: limit.resetsAt,
                windowDurationMinutes: duration,
                severity: limit.severity,
                isActive: limit.isActive
            )
        }
    }

    /// Fallback for responses that predate the `limits[]` array.
    private func windowsFromLegacyFields() -> [QuotaWindow] {
        var windows: [QuotaWindow] = []

        if let fh = fiveHour {
            windows.append(QuotaWindow(
                id: "session",
                displayName: "Session (5h)",
                usagePercent: fh.utilization ?? 0,
                resetsAt: fh.resetsAt,
                windowDurationMinutes: 300
            ))
        }

        if let sd = sevenDay {
            windows.append(QuotaWindow(
                id: "weekly",
                displayName: "Weekly",
                usagePercent: sd.utilization ?? 0,
                resetsAt: sd.resetsAt,
                windowDurationMinutes: 10080
            ))
        }

        if let opus = sevenDayOpus {
            windows.append(QuotaWindow(
                id: "weekly-opus",
                displayName: "Opus Weekly",
                usagePercent: opus.utilization ?? 0,
                resetsAt: opus.resetsAt,
                windowDurationMinutes: 10080
            ))
        }

        if let sonnet = sevenDaySonnet {
            windows.append(QuotaWindow(
                id: "weekly-sonnet",
                displayName: "Sonnet Weekly",
                usagePercent: sonnet.utilization ?? 0,
                resetsAt: sonnet.resetsAt,
                windowDurationMinutes: 10080
            ))
        }

        return windows
    }
}

// MARK: - Claude.json (global config)

/// The ~/.claude.json file containing account info
struct ClaudeGlobalConfig: Decodable {
    let oauthAccount: OAuthAccount?
    let userID: String?
    let firstStartTime: String?

    struct OAuthAccount: Decodable {
        let accountUuid: String?
        let emailAddress: String?
        let organizationUuid: String?
        let organizationName: String?
        let organizationRole: String?
        let displayName: String?
        let hasExtraUsageEnabled: Bool?
        let subscriptionType: String?   // "max", "pro", etc.
    }
}

// MARK: - Keychain OAuth Credentials

/// OAuth credentials stored in macOS Keychain
struct ClaudeOAuthCredentials: Decodable {
    let claudeAiOauth: OAuthData?
    let primaryApiKey: String?

    /// Explicit initializer (used when constructing from direct OAuthData decode)
    init(claudeAiOauth: OAuthData?, primaryApiKey: String?) {
        self.claudeAiOauth = claudeAiOauth
        self.primaryApiKey = primaryApiKey
    }

    struct OAuthData: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiresAt: Int64?           // Unix timestamp in milliseconds
        let scopes: [String]?
        let subscriptionType: String?
        let rateLimitTier: String?

        var isExpired: Bool {
            guard let expiresAt = expiresAt else { return true }
            return Date().timeIntervalSince1970 * 1000 > Double(expiresAt)
        }
    }
}

// MARK: - Credentials File

/// Structure of ~/.claude/.credentials.json
struct ClaudeCredentialsFile: Decodable {
    let claudeAiOauth: ClaudeOAuthCredentials.OAuthData?

    enum CodingKeys: String, CodingKey {
        case claudeAiOauth = "claude_ai_oauth"
    }
}
