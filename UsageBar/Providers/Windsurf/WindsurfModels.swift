import Foundation

// MARK: - Windsurf/Codeium Analytics Response

/// Response from POST https://server.codeium.com/api/v1/Analytics
struct WindsurfAnalyticsResponse: Decodable {
    let data: [WindsurfAnalyticsRow]?

    struct WindsurfAnalyticsRow: Decodable {
        let timestamp: String?
        let email: String?
        let ideType: String?
        let numAcceptances: Int?
        let numLinesAccepted: Int?
        let numSuggestions: Int?

        enum CodingKeys: String, CodingKey {
            case timestamp
            case email
            case ideType = "ide_type"
            case numAcceptances = "num_acceptances"
            case numLinesAccepted = "num_lines_accepted"
            case numSuggestions = "num_suggestions"
        }
    }
}

// MARK: - Windsurf Cascade Analytics Response

/// Response from POST https://server.codeium.com/api/v1/CascadeAnalytics
struct WindsurfCascadeResponse: Decodable {
    let data: [CascadeDayEntry]?

    struct CascadeDayEntry: Decodable {
        let date: String?
        let linesSuggested: Int?
        let linesAccepted: Int?
        let toolCalls: Int?

        enum CodingKeys: String, CodingKey {
            case date
            case linesSuggested = "lines_suggested"
            case linesAccepted = "lines_accepted"
            case toolCalls = "tool_calls"
        }
    }
}

// MARK: - Windsurf Credit Info (from plan page scraping or local display)

/// Simplified credit tracking for individual users
struct WindsurfCreditInfo {
    let creditsUsed: Int
    let creditsTotal: Int
    let planName: String  // "Free", "Pro", "Teams"

    var creditsRemaining: Int { creditsTotal - creditsUsed }
    var usagePercent: Double {
        guard creditsTotal > 0 else { return 0 }
        return Double(creditsUsed) / Double(creditsTotal)
    }
}
