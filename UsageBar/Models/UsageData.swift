import Foundation

/// Represents aggregated usage data from a single provider
struct UsageData: Identifiable, Equatable {
    let id = UUID()
    let provider: String
    let period: UsagePeriod
    let totalCostUSD: Decimal
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let breakdown: [UsageBreakdown]
    let dailyTrend: [DailyUsage]
    let fetchedAt: Date

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }

    static func == (lhs: UsageData, rhs: UsageData) -> Bool {
        lhs.id == rhs.id
    }

    static var empty: UsageData {
        UsageData(
            provider: "",
            period: .today,
            totalCostUSD: 0,
            inputTokens: 0,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            breakdown: [],
            dailyTrend: [],
            fetchedAt: Date()
        )
    }
}

/// Per-model breakdown of usage
struct UsageBreakdown: Identifiable, Hashable {
    let id = UUID()
    let model: String
    let costUSD: Decimal
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }
}

/// Daily usage for trend charts
struct DailyUsage: Identifiable {
    let id = UUID()
    let date: Date
    let costUSD: Decimal
    let inputTokens: Int
    let outputTokens: Int
}
