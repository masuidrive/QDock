import Foundation

// MARK: - Usage Report Response

struct AnthropicUsageResponse: Decodable {
    let data: [AnthropicUsageBucket]

    struct AnthropicUsageBucket: Decodable {
        let startTime: String
        let endTime: String
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreation: CacheCreation?
        let numMessages: Int?
        let model: String?
        let workspaceId: String?
        let apiKeyId: String?

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
            case startTime = "start_time"
            case endTime = "end_time"
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case cacheCreation = "cache_creation"
            case numMessages = "num_messages"
            case model
            case workspaceId = "workspace_id"
            case apiKeyId = "api_key_id"
        }
    }
}

// MARK: - Cost Report Response

struct AnthropicCostResponse: Decodable {
    let data: [AnthropicCostEntry]

    struct AnthropicCostEntry: Decodable {
        let currency: String
        let amount: String  // Cost in cents as decimal string
        let model: String?
        let description: String?
        let costType: String?
        let tokenType: String?
        let serviceTier: String?

        /// Cost in USD (amount is in cents)
        var costUSD: Decimal {
            guard let cents = Decimal(string: amount) else { return 0 }
            return cents / 100
        }

        enum CodingKeys: String, CodingKey {
            case currency
            case amount
            case model
            case description
            case costType = "cost_type"
            case tokenType = "token_type"
            case serviceTier = "service_tier"
        }
    }
}
