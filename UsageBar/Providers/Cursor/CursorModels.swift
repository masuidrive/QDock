import Foundation

// MARK: - Cursor Usage Response

/// Response from GET https://www.cursor.com/api/usage
struct CursorUsageResponse: Decodable {
    let premiumRequests: CursorPremiumRequests?
    let usageBasedPricing: CursorUsageBasedPricing?

    struct CursorPremiumRequests: Decodable {
        let current: Int?
        let limit: Int?
    }

    struct CursorUsageBasedPricing: Decodable {
        let totalCost: Double?
        let limit: Double?
        let isEnabled: Bool?
    }

    enum CodingKeys: String, CodingKey {
        case premiumRequests
        case usageBasedPricing
    }
}

// MARK: - Cursor Monthly Invoice Response

/// Response from POST https://www.cursor.com/api/dashboard/get-monthly-invoice
struct CursorInvoiceResponse: Decodable {
    let items: [CursorInvoiceItem]?
    let totalCents: Int?

    struct CursorInvoiceItem: Decodable {
        let description: String?
        let amountCents: Int?
        let model: String?
        let numRequests: Int?
        let inputTokens: Int?
        let outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case description
            case amountCents = "amount_cents"
            case model
            case numRequests = "num_requests"
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    enum CodingKeys: String, CodingKey {
        case items
        case totalCents = "total_cents"
    }
}

// MARK: - Cursor Hard Limit Response

struct CursorHardLimitResponse: Decodable {
    let hardLimit: Double?
    let noUsageBasedAllowed: Bool?
}

// MARK: - Cursor Stripe Profile

struct CursorStripeProfile: Decodable {
    let membershipType: String?  // "pro", "free", "business", etc.

    enum CodingKeys: String, CodingKey {
        case membershipType = "membership_type"
    }
}
