import Foundation

// MARK: - Claude Usage API Response

/// Response from GET https://api.anthropic.com/api/oauth/usage
///
/// NOTE: No explicit CodingKeys here — NetworkClient uses
/// `keyDecodingStrategy = .convertFromSnakeCase` which automatically
/// maps `five_hour` → `fiveHour`, `resets_at` → `resetsAt`, etc.
/// Adding manual CodingKeys would double-convert and break decoding.
struct ClaudeUsageResponse: Decodable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?

    struct UsageWindow: Decodable {
        let utilization: Double?        // 0.0 - 100.0
        let resetsAt: Date?             // ISO8601 date (decoded by .iso8601 strategy)
    }

    /// Convert to QuotaData
    func toQuotaData(provider: String, planName: String?, email: String?) -> QuotaData {
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
                id: "sonnet",
                displayName: "Sonnet Limit",
                usagePercent: opus.utilization ?? 0,
                resetsAt: opus.resetsAt,
                windowDurationMinutes: 10080
            ))
        }

        return QuotaData(
            id: "claude-code",
            provider: provider,
            planName: planName,
            windows: windows,
            accountEmail: email,
            fetchedAt: Date(),
            isStale: false
        )
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
