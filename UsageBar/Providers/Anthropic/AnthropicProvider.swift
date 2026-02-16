import Foundation

/// Anthropic usage provider using the Admin API
final class AnthropicProvider: UsageProvider {
    let id = "anthropic"
    let name = "Anthropic"
    let iconName = "brain.head.profile"
    let brandColorHex = "#D4A574"
    var isEnabled: Bool = true

    let apiKeyDescription = "Requires an Admin API key (starts with sk-ant-admin...). Create one in Console → Settings → Admin Keys."
    let apiKeyPlaceholder = "sk-ant-admin01-..."

    private let baseURL = "https://api.anthropic.com/v1/organizations"
    private let keychainKey = "anthropic-api-key"
    private let apiVersion = "2023-06-01"

    var isConfigured: Bool {
        guard let key = KeychainService.shared.get(key: keychainKey) else { return false }
        return key.hasPrefix("sk-ant-admin")
    }

    private var apiKey: String? {
        KeychainService.shared.get(key: keychainKey)
    }

    private var headers: [String: String] {
        guard let key = apiKey else { return [:] }
        return [
            "x-api-key": key,
            "anthropic-version": apiVersion,
            "Content-Type": "application/json",
        ]
    }

    // MARK: - Fetch Usage

    func fetchUsage(for period: UsagePeriod) async throws -> UsageData {
        guard isConfigured else { throw ProviderError.notConfigured }

        // Fetch usage and cost in parallel
        async let usageResult = fetchTokenUsage(for: period)
        async let costResult = fetchCostReport(for: period)
        async let trendResult = fetchDailyTrend(for: period)

        let (usage, cost, trend) = try await (usageResult, costResult, trendResult)

        return UsageData(
            provider: name,
            period: period,
            totalCostUSD: cost.totalCost,
            inputTokens: usage.totalInput,
            outputTokens: usage.totalOutput,
            cacheReadTokens: usage.totalCacheRead,
            cacheCreationTokens: usage.totalCacheCreation,
            breakdown: usage.breakdown,
            dailyTrend: trend,
            fetchedAt: Date()
        )
    }

    // MARK: - Validate

    func validate() async throws -> Bool {
        guard let key = apiKey, key.hasPrefix("sk-ant-admin") else {
            throw ProviderError.invalidAPIKey
        }

        // Try fetching a tiny usage report to validate the key
        let formatter = ISO8601DateFormatter()
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)

        var components = URLComponents(string: "\(baseURL)/usage_report/messages")!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: formatter.string(from: startOfToday)),
            URLQueryItem(name: "ending_at", value: formatter.string(from: now)),
            URLQueryItem(name: "bucket_width", value: "1d"),
        ]

        _ = try await NetworkClient.shared.get(
            url: components.url!,
            headers: headers,
            responseType: AnthropicUsageResponse.self
        )

        return true
    }

    // MARK: - Private Helpers

    private struct AggregatedUsage {
        let totalInput: Int
        let totalOutput: Int
        let totalCacheRead: Int
        let totalCacheCreation: Int
        let breakdown: [UsageBreakdown]
    }

    private struct AggregatedCost {
        let totalCost: Decimal
    }

    private func fetchTokenUsage(for period: UsagePeriod) async throws -> AggregatedUsage {
        let formatter = ISO8601DateFormatter()

        var components = URLComponents(string: "\(baseURL)/usage_report/messages")!
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

        // Aggregate by model
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
                costUSD: 0, // Cost comes from cost endpoint
                inputTokens: data.input,
                outputTokens: data.output,
                cacheReadTokens: data.cacheRead,
                cacheCreationTokens: data.cacheCreation
            )
        }.sorted { $0.totalTokens > $1.totalTokens }

        return AggregatedUsage(
            totalInput: modelData.values.reduce(0) { $0 + $1.input },
            totalOutput: modelData.values.reduce(0) { $0 + $1.output },
            totalCacheRead: modelData.values.reduce(0) { $0 + $1.cacheRead },
            totalCacheCreation: modelData.values.reduce(0) { $0 + $1.cacheCreation },
            breakdown: breakdown
        )
    }

    private func fetchCostReport(for period: UsagePeriod) async throws -> AggregatedCost {
        let formatter = ISO8601DateFormatter()

        var components = URLComponents(string: "\(baseURL)/cost_report")!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: formatter.string(from: period.startDate)),
            URLQueryItem(name: "ending_at", value: formatter.string(from: period.endDate)),
        ]

        let response = try await NetworkClient.shared.get(
            url: components.url!,
            headers: headers,
            responseType: AnthropicCostResponse.self
        )

        let totalCost = response.data.reduce(Decimal(0)) { $0 + $1.costUSD }

        return AggregatedCost(totalCost: totalCost)
    }

    private func fetchDailyTrend(for period: UsagePeriod) async throws -> [DailyUsage] {
        // For today/yesterday, return empty (not enough data for a trend)
        guard period == .last7Days || period == .last30Days || period == .thisMonth else {
            return []
        }

        let formatter = ISO8601DateFormatter()

        var components = URLComponents(string: "\(baseURL)/usage_report/messages")!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: formatter.string(from: period.startDate)),
            URLQueryItem(name: "ending_at", value: formatter.string(from: period.endDate)),
            URLQueryItem(name: "bucket_width", value: "1d"),
        ]

        let response = try await NetworkClient.shared.get(
            url: components.url!,
            headers: headers,
            responseType: AnthropicUsageResponse.self
        )

        let dateFormatter = ISO8601DateFormatter()

        return response.data.compactMap { bucket in
            guard let date = dateFormatter.date(from: bucket.startTime) else { return nil }
            return DailyUsage(
                date: date,
                costUSD: 0,
                inputTokens: bucket.inputTokens ?? 0,
                outputTokens: bucket.outputTokens ?? 0
            )
        }
    }
}
