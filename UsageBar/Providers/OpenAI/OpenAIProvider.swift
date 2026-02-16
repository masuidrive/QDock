import Foundation

/// OpenAI usage provider
/// Uses the OpenAI organization usage API
final class OpenAIProvider: UsageProvider {
    let id = "openai"
    let name = "OpenAI"
    let iconName = "sparkles"
    let brandColorHex = "#10A37F"
    var isEnabled: Bool = false

    let apiKeyDescription = "Requires an OpenAI API key with organization usage permissions."
    let apiKeyPlaceholder = "sk-..."

    private let baseURL = "https://api.openai.com/v1/organization"
    private let keychainKey = "openai-api-key"

    var isConfigured: Bool {
        guard let key = KeychainService.shared.get(key: keychainKey) else { return false }
        return !key.isEmpty
    }

    private var apiKey: String? {
        KeychainService.shared.get(key: keychainKey)
    }

    private var headers: [String: String] {
        guard let key = apiKey else { return [:] }
        return [
            "Authorization": "Bearer \(key)",
            "Content-Type": "application/json",
        ]
    }

    func fetchUsage(for period: UsagePeriod) async throws -> UsageData {
        guard isConfigured else { throw ProviderError.notConfigured }

        let startTimestamp = Int(period.startDate.timeIntervalSince1970)
        let endTimestamp = Int(period.endDate.timeIntervalSince1970)

        // Fetch completions usage
        var components = URLComponents(string: "\(baseURL)/usage/completions")!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: String(startTimestamp)),
            URLQueryItem(name: "end_time", value: String(endTimestamp)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "group_by[]", value: "model"),
        ]

        let response = try await NetworkClient.shared.get(
            url: components.url!,
            headers: headers,
            responseType: OpenAIUsageResponse.self
        )

        // Aggregate data
        var modelData: [String: (input: Int, output: Int, cached: Int)] = [:]
        for bucket in response.data {
            for result in bucket.results ?? [] {
                let model = result.model ?? "unknown"
                var current = modelData[model] ?? (0, 0, 0)
                current.input += result.inputTokens ?? 0
                current.output += result.outputTokens ?? 0
                current.cached += result.inputCachedTokens ?? 0
                modelData[model] = current
            }
        }

        let breakdown = modelData.map { model, data in
            UsageBreakdown(
                model: model,
                costUSD: 0,
                inputTokens: data.input,
                outputTokens: data.output,
                cacheReadTokens: data.cached,
                cacheCreationTokens: 0
            )
        }.sorted { $0.totalTokens > $1.totalTokens }

        // Try to fetch cost data
        let totalCost = await fetchCost(start: startTimestamp, end: endTimestamp)

        return UsageData(
            provider: name,
            period: period,
            totalCostUSD: totalCost,
            inputTokens: modelData.values.reduce(0) { $0 + $1.input },
            outputTokens: modelData.values.reduce(0) { $0 + $1.output },
            cacheReadTokens: modelData.values.reduce(0) { $0 + $1.cached },
            cacheCreationTokens: 0,
            breakdown: breakdown,
            dailyTrend: [],
            fetchedAt: Date()
        )
    }

    func validate() async throws -> Bool {
        guard isConfigured else { throw ProviderError.invalidAPIKey }

        let now = Int(Date().timeIntervalSince1970)
        let oneDayAgo = now - 86400

        var components = URLComponents(string: "\(baseURL)/usage/completions")!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: String(oneDayAgo)),
            URLQueryItem(name: "end_time", value: String(now)),
            URLQueryItem(name: "bucket_width", value: "1d"),
        ]

        _ = try await NetworkClient.shared.get(
            url: components.url!,
            headers: headers,
            responseType: OpenAIUsageResponse.self
        )

        return true
    }

    private func fetchCost(start: Int, end: Int) async -> Decimal {
        var components = URLComponents(string: "\(baseURL)/costs")
        components?.queryItems = [
            URLQueryItem(name: "start_time", value: String(start)),
            URLQueryItem(name: "end_time", value: String(end)),
            URLQueryItem(name: "bucket_width", value: "1d"),
        ]

        guard let url = components?.url else { return 0 }

        do {
            let response = try await NetworkClient.shared.get(
                url: url,
                headers: headers,
                responseType: OpenAICostResponse.self
            )
            var total: Double = 0
            for bucket in response.data {
                for result in bucket.results ?? [] {
                    total += result.amount?.value ?? 0
                }
            }
            // OpenAI returns cost in cents
            return Decimal(total) / 100
        } catch {
            return 0
        }
    }
}
