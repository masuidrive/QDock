import Foundation

// MARK: - OpenAI Usage Response

/// OpenAI usage API response models
/// Endpoint: GET https://api.openai.com/v1/organization/usage/completions
struct OpenAIUsageResponse: Decodable {
    let object: String?
    let data: [OpenAIUsageBucket]
    let hasMore: Bool?
    let nextPage: String?

    struct OpenAIUsageBucket: Decodable {
        let startTime: Int?  // Unix timestamp
        let endTime: Int?
        let results: [OpenAIUsageResult]?

        struct OpenAIUsageResult: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            let inputCachedTokens: Int?
            let numModelRequests: Int?
            let model: String?
            let projectId: String?

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case inputCachedTokens = "input_cached_tokens"
                case numModelRequests = "num_model_requests"
                case model
                case projectId = "project_id"
            }
        }

        enum CodingKeys: String, CodingKey {
            case startTime = "start_time"
            case endTime = "end_time"
            case results
        }
    }

    enum CodingKeys: String, CodingKey {
        case object
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

// MARK: - OpenAI Cost Response

struct OpenAICostResponse: Decodable {
    let object: String?
    let data: [OpenAICostBucket]

    struct OpenAICostBucket: Decodable {
        let startTime: Int?
        let results: [OpenAICostResult]?

        struct OpenAICostResult: Decodable {
            let amount: OpenAICostAmount?
            let lineItem: String?

            struct OpenAICostAmount: Decodable {
                let value: Double?
                let currency: String?
            }

            enum CodingKeys: String, CodingKey {
                case amount
                case lineItem = "line_item"
            }
        }

        enum CodingKeys: String, CodingKey {
            case startTime = "start_time"
            case results
        }
    }

    enum CodingKeys: String, CodingKey {
        case object
        case data
    }
}
