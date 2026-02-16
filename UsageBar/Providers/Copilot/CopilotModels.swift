import Foundation

// MARK: - Copilot Metrics Response (GA API)

/// Response from GET /orgs/{org}/copilot/metrics
struct CopilotMetricsResponse: Decodable {
    // The response is an array at the top level
}

/// A single day of Copilot metrics
struct CopilotMetricsDay: Decodable {
    let date: String?
    let totalActiveUsers: Int?
    let totalEngagedUsers: Int?
    let copilotIdeCodeCompletions: CopilotCodeCompletions?
    let copilotIdeChat: CopilotChat?
    let copilotDotcomChat: CopilotChat?
    let copilotDotcomPullRequests: CopilotPRSummary?

    struct CopilotCodeCompletions: Decodable {
        let totalEngagedUsers: Int?
        let editors: [EditorMetric]?

        struct EditorMetric: Decodable {
            let name: String?
            let totalEngagedUsers: Int?
            let models: [ModelMetric]?

            struct ModelMetric: Decodable {
                let name: String?
                let isCustomModel: Bool?
                let totalEngagedUsers: Int?
                let languages: [LanguageMetric]?

                struct LanguageMetric: Decodable {
                    let name: String?
                    let totalEngagedUsers: Int?
                    let totalCodeSuggestions: Int?
                    let totalCodeAcceptances: Int?
                    let totalCodeLinesSuggested: Int?
                    let totalCodeLinesAccepted: Int?

                    enum CodingKeys: String, CodingKey {
                        case name
                        case totalEngagedUsers = "total_engaged_users"
                        case totalCodeSuggestions = "total_code_suggestions"
                        case totalCodeAcceptances = "total_code_acceptances"
                        case totalCodeLinesSuggested = "total_code_lines_suggested"
                        case totalCodeLinesAccepted = "total_code_lines_accepted"
                    }
                }

                enum CodingKeys: String, CodingKey {
                    case name
                    case isCustomModel = "is_custom_model"
                    case totalEngagedUsers = "total_engaged_users"
                    case languages
                }
            }

            enum CodingKeys: String, CodingKey {
                case name
                case totalEngagedUsers = "total_engaged_users"
                case models
            }
        }

        enum CodingKeys: String, CodingKey {
            case totalEngagedUsers = "total_engaged_users"
            case editors
        }
    }

    struct CopilotChat: Decodable {
        let totalEngagedUsers: Int?
        let totalChats: Int?

        enum CodingKeys: String, CodingKey {
            case totalEngagedUsers = "total_engaged_users"
            case totalChats = "total_chats"
        }
    }

    struct CopilotPRSummary: Decodable {
        let totalEngagedUsers: Int?
        let totalPrSummariesCreated: Int?

        enum CodingKeys: String, CodingKey {
            case totalEngagedUsers = "total_engaged_users"
            case totalPrSummariesCreated = "total_pr_summaries_created"
        }
    }

    enum CodingKeys: String, CodingKey {
        case date
        case totalActiveUsers = "total_active_users"
        case totalEngagedUsers = "total_engaged_users"
        case copilotIdeCodeCompletions = "copilot_ide_code_completions"
        case copilotIdeChat = "copilot_ide_chat"
        case copilotDotcomChat = "copilot_dotcom_chat"
        case copilotDotcomPullRequests = "copilot_dotcom_pull_requests"
    }
}

// MARK: - Individual Billing Usage

/// Response from GET /users/{username}/settings/billing/premium_request/usage
struct CopilotBillingUsage: Decodable {
    let premiumRequestsUsed: Int?
    let premiumRequestsIncluded: Int?
    let billingCycleStart: String?
    let billingCycleEnd: String?

    enum CodingKeys: String, CodingKey {
        case premiumRequestsUsed = "premium_requests_used"
        case premiumRequestsIncluded = "premium_requests_included"
        case billingCycleStart = "billing_cycle_start"
        case billingCycleEnd = "billing_cycle_end"
    }
}
