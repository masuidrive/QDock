import Foundation

// MARK: - Session JSONL Message Types

/// A single line from a Claude Code session JSONL file
struct SessionMessage: Decodable {
    let type: String                    // "user", "assistant", "system", etc.
    let message: AssistantMessage?      // Present for "assistant" type
    let sessionId: String?
    let timestamp: String?
    let model: String?
    let cwd: String?
    let version: String?
    let gitBranch: String?
    let uuid: String?
    let parentUuid: String?
    let requestId: String?
    let costUSD: Double?

    struct AssistantMessage: Decodable {
        let usage: TokenUsage?
        let model: String?
        let role: String?
    }

    struct TokenUsage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreation: CacheCreation?
        let serviceTier: String?

        struct CacheCreation: Decodable {
            let ephemeral5mInputTokens: Int?
            let ephemeral1hInputTokens: Int?

            var totalTokens: Int {
                (ephemeral5mInputTokens ?? 0) + (ephemeral1hInputTokens ?? 0)
            }

            enum CodingKeys: String, CodingKey {
                case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
                case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
            }
        }

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case cacheCreation = "cache_creation"
            case serviceTier = "service_tier"
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, message, sessionId, timestamp, model, cwd
        case version, gitBranch, uuid, parentUuid, requestId, costUSD
    }
}

// MARK: - Stats Cache (stats-cache.json)

/// Claude Code's local stats cache at ~/.claude/stats-cache.json
struct StatsCache: Decodable {
    let version: Int?
    let dailyActivity: [DailyActivityEntry]?
    let dailyModelTokens: [DailyModelTokenEntry]?
    let modelUsage: [String: ModelUsageEntry]?
    let totalSessions: Int?
    let totalMessages: Int?
    let longestSession: LongestSession?
    let firstSessionDate: String?
    let hourCounts: [String: Int]?
    let lastComputedDate: String?
    let totalSpeculationTimeSavedMs: Int?

    struct DailyActivityEntry: Decodable {
        let date: String
        let messageCount: Int?
        let sessionCount: Int?
        let toolCallCount: Int?
    }

    struct DailyModelTokenEntry: Decodable {
        let date: String
        let tokensByModel: [String: Int]?
    }

    struct ModelUsageEntry: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreationInputTokens: Int?
        let webSearchRequests: Int?
        let costUSD: Double?
        let contextWindow: Int?
        let maxOutputTokens: Int?
    }

    struct LongestSession: Decodable {
        let sessionId: String?
        let duration: Int?
        let messageCount: Int?
        let timestamp: String?
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

// MARK: - Parsed Session Summary

/// A parsed and summarized Claude Code session
struct ClaudeCodeSession: Identifiable {
    let id: String              // session UUID (filename)
    let projectPath: String
    let startTime: Date?
    let endTime: Date?
    let messageCount: Int
    let model: String?
    let gitBranch: String?
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let totalCacheReadTokens: Int
    let totalCacheCreationTokens: Int
    let costUSD: Double
    let models: Set<String>

    var totalTokens: Int {
        totalInputTokens + totalOutputTokens + totalCacheReadTokens + totalCacheCreationTokens
    }

    var duration: TimeInterval? {
        guard let start = startTime, let end = endTime else { return nil }
        return end.timeIntervalSince(start)
    }

    var durationFormatted: String {
        guard let duration = duration else { return "—" }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
