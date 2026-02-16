import Foundation

// MARK: - OpenRouter Key Info Response

/// OpenRouter API key info response
/// Endpoint: GET https://openrouter.ai/api/v1/auth/key
struct OpenRouterKeyResponse: Decodable {
    let data: OpenRouterKeyData

    struct OpenRouterKeyData: Decodable {
        let label: String?
        let usage: Double?          // Total credits used in USD
        let limit: Double?          // Credit limit, nil = unlimited
        let isFreeTier: Bool?
        let rateLimit: OpenRouterRateLimit?

        struct OpenRouterRateLimit: Decodable {
            let requests: Int?
            let interval: String?
        }

        enum CodingKeys: String, CodingKey {
            case label
            case usage
            case limit
            case isFreeTier = "is_free_tier"
            case rateLimit = "rate_limit"
        }
    }
}

// MARK: - OpenRouter Activity Response

/// OpenRouter activity/generation stats
/// Endpoint: GET https://openrouter.ai/api/v1/activity
struct OpenRouterActivityResponse: Decodable {
    let data: [OpenRouterActivity]

    struct OpenRouterActivity: Decodable {
        let id: String?
        let model: String?
        let totalCost: Double?
        let promptTokens: Int?
        let completionTokens: Int?
        let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case model
            case totalCost = "total_cost"
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case createdAt = "created_at"
        }
    }
}
