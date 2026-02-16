import Foundation

/// Fallback: Uses the OAuth access token from Keychain to query Anthropic API
/// when local session files are not available (e.g., fresh install, remote usage)
final class OAuthAPIFallback {

    /// Check if OAuth fallback is available
    static var isAvailable: Bool {
        ClaudeKeychainReader.accessToken != nil
    }

    /// Fetch usage via OAuth token — calls the sessions endpoint
    /// This gets recent session data from the Anthropic API using the OAuth token
    static func fetchRecentUsage(for period: UsagePeriod) async throws -> UsageData {
        guard let token = ClaudeKeychainReader.accessToken else {
            throw ProviderError.notConfigured
        }

        let headers = [
            "Authorization": "Bearer \(token)",
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
        ]

        // Use the organization usage endpoint via OAuth
        let formatter = ISO8601DateFormatter()
        let baseURL = "https://api.anthropic.com/v1/organizations/usage_report/messages"

        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: formatter.string(from: period.startDate)),
            URLQueryItem(name: "ending_at", value: formatter.string(from: period.endDate)),
            URLQueryItem(name: "bucket_width", value: period.bucketWidth),
            URLQueryItem(name: "group_by[]", value: "model"),
        ]

        let response = try await NetworkClient.shared.get(
            url: components.url!,
            headers: headers,
            responseType: AnthropicUsageResponse.self
        )

        // Aggregate
        var modelData: [String: (input: Int, output: Int, cacheRead: Int, cacheCreation: Int)] = [:]

        for bucket in response.data {
            let model = bucket.model ?? "unknown"
            var current = modelData[model] ?? (0, 0, 0, 0)
            current.input += bucket.inputTokens ?? 0
            current.output += bucket.outputTokens ?? 0
            current.cacheRead += bucket.cacheReadInputTokens ?? 0
            current.cacheCreation += bucket.cacheCreation?.totalTokens ?? 0
            modelData[model] = current
        }

        let breakdown = modelData.map { model, data in
            UsageBreakdown(
                model: model,
                costUSD: 0,
                inputTokens: data.input,
                outputTokens: data.output,
                cacheReadTokens: data.cacheRead,
                cacheCreationTokens: data.cacheCreation
            )
        }.sorted { $0.totalTokens > $1.totalTokens }

        return UsageData(
            provider: "Claude Code (API)",
            period: period,
            totalCostUSD: 0,
            inputTokens: modelData.values.reduce(0) { $0 + $1.input },
            outputTokens: modelData.values.reduce(0) { $0 + $1.output },
            cacheReadTokens: modelData.values.reduce(0) { $0 + $1.cacheRead },
            cacheCreationTokens: modelData.values.reduce(0) { $0 + $1.cacheCreation },
            breakdown: breakdown,
            dailyTrend: [],
            fetchedAt: Date()
        )
    }
}
