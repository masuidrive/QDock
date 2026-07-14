import Foundation

// MARK: - Codex JSON-RPC Models

/// JSON-RPC response envelope
struct JsonRpcResponse: Decodable {
    let jsonrpc: String?
    let id: Int?
    let result: JsonRpcResult?
    let error: JsonRpcError?
    let method: String?
}

struct JsonRpcResult: Decodable {
    let capabilities: ServerCapabilities?
    let userAgent: String?
    let rateLimits: RateLimitsResult?
    let rateLimitsByLimitId: [String: RateLimitsResult]?

    enum CodingKeys: String, CodingKey {
        case capabilities
        case userAgent
        case rateLimits
        case rateLimitsLegacy = "rate_limits"
        case rateLimitsByLimitId
        case rateLimitsByLimitIdLegacy = "rate_limits_by_limit_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        capabilities = try container.decodeIfPresent(ServerCapabilities.self, forKey: .capabilities)
        userAgent = try container.decodeIfPresent(String.self, forKey: .userAgent)

        rateLimits = try container.decodeIfPresent(RateLimitsResult.self, forKey: .rateLimits)
            ?? container.decodeIfPresent(RateLimitsResult.self, forKey: .rateLimitsLegacy)

        rateLimitsByLimitId = try container.decodeIfPresent([String: RateLimitsResult].self, forKey: .rateLimitsByLimitId)
            ?? container.decodeIfPresent([String: RateLimitsResult].self, forKey: .rateLimitsByLimitIdLegacy)
    }

    /// Prefer the metered Codex bucket when available.
    var resolvedRateLimits: RateLimitsResult? {
        if let buckets = rateLimitsByLimitId {
            if let codexBucket = buckets["codex"] {
                return codexBucket
            }
            if let firstBucket = buckets.values.first {
                return firstBucket
            }
        }
        return rateLimits
    }
}

struct ServerCapabilities: Decodable {
    let name: String?
    let version: String?
}

struct JsonRpcError: Decodable {
    let code: Int?
    let message: String?
}

// MARK: - Rate Limits

struct RateLimitsResult: Decodable {
    let limitId: String?
    let limitName: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let credits: CodexCredits?
    let planType: String?
    let rateLimitReachedType: String?

    enum CodingKeys: String, CodingKey {
        case limitId
        case limitIdLegacy = "limit_id"
        case limitName
        case limitNameLegacy = "limit_name"
        case primary
        case secondary
        case credits
        case planType
        case planTypeLegacy = "plan_type"
        case rateLimitReachedType
        case rateLimitReachedTypeLegacy = "rate_limit_reached_type"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limitId = try container.decodeIfPresent(String.self, forKey: .limitId)
            ?? container.decodeIfPresent(String.self, forKey: .limitIdLegacy)
        limitName = try container.decodeIfPresent(String.self, forKey: .limitName)
            ?? container.decodeIfPresent(String.self, forKey: .limitNameLegacy)
        primary = try container.decodeIfPresent(RateLimitWindow.self, forKey: .primary)
        secondary = try container.decodeIfPresent(RateLimitWindow.self, forKey: .secondary)
        credits = try container.decodeIfPresent(CodexCredits.self, forKey: .credits)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
            ?? container.decodeIfPresent(String.self, forKey: .planTypeLegacy)
        rateLimitReachedType = try container.decodeIfPresent(String.self, forKey: .rateLimitReachedType)
            ?? container.decodeIfPresent(String.self, forKey: .rateLimitReachedTypeLegacy)
    }
}

/// Purchased credit state reported alongside rate limits (app-server v2)
struct CodexCredits: Decodable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let balance: Double?

    enum CodingKeys: String, CodingKey {
        case hasCredits
        case hasCreditsLegacy = "has_credits"
        case unlimited
        case balance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = try container.decodeIfPresent(Bool.self, forKey: .hasCredits)
            ?? container.decodeIfPresent(Bool.self, forKey: .hasCreditsLegacy)
        unlimited = try container.decodeIfPresent(Bool.self, forKey: .unlimited)
        // Balance arrives as a number or a numeric string depending on version.
        if let value = try? container.decode(Double.self, forKey: .balance) {
            balance = value
        } else if let value = try? container.decode(Int.self, forKey: .balance) {
            balance = Double(value)
        } else if let value = try? container.decode(String.self, forKey: .balance) {
            balance = Double(value)
        } else {
            balance = nil
        }
    }
}

struct RateLimitWindow: Decodable {
    let usedPercent: Double?
    let resetsAt: Int?              // Unix timestamp
    let windowDurationMins: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent
        case resetsAt
        case windowDurationMins
        case usedPercentLegacy = "used_percent"
        case resetsAtLegacy = "resets_at"
        case windowDurationMinsLegacy = "window_duration_mins"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        usedPercent = Self.decodePercent(from: container, key: .usedPercent)
            ?? Self.decodePercent(from: container, key: .usedPercentLegacy)

        resetsAt = try container.decodeIfPresent(Int.self, forKey: .resetsAt)
            ?? container.decodeIfPresent(Int.self, forKey: .resetsAtLegacy)

        windowDurationMins = try container.decodeIfPresent(Int.self, forKey: .windowDurationMins)
            ?? container.decodeIfPresent(Int.self, forKey: .windowDurationMinsLegacy)
    }

    private static func decodePercent(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? container.decode(String.self, forKey: key),
           let percent = Double(value) {
            return percent
        }
        return nil
    }
}

// MARK: - Codex Config

/// Codex configuration from ~/.codex/config.toml (simplified key-value extraction)
struct CodexConfig {
    let model: String?
    let provider: String?

    static func read() -> CodexConfig? {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml")
        guard let content = try? String(contentsOf: configPath, encoding: .utf8) else {
            return nil
        }

        return CodexConfig(
            model: extractTOMLValue(from: content, key: "model"),
            provider: extractTOMLValue(from: content, key: "provider")
        )
    }

    private static func extractTOMLValue(from content: String, section: String? = nil, key: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        var inSection = section == nil

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") {
                let sectionName = trimmed
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    .trimmingCharacters(in: .whitespaces)
                inSection = (section == nil) || (sectionName == section)
                continue
            }

            guard inSection else { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let foundKey = parts[0].trimmingCharacters(in: .whitespaces)
            if foundKey == key {
                return parts[1]
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }

        return nil
    }
}
