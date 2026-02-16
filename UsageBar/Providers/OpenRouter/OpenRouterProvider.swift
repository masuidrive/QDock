import Foundation

/// OpenRouter usage provider
final class OpenRouterProvider: UsageProvider {
    let id = "openrouter"
    let name = "OpenRouter"
    let iconName = "arrow.triangle.branch"
    let brandColorHex = "#6366F1"
    var isEnabled: Bool = false

    let apiKeyDescription = "Requires an OpenRouter API key. Get one at openrouter.ai/keys."
    let apiKeyPlaceholder = "sk-or-..."

    private let baseURL = "https://openrouter.ai/api/v1"
    private let keychainKey = "openrouter-api-key"

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

        // OpenRouter provides total usage via key info
        let keyInfo = try await fetchKeyInfo()

        // Try to get detailed activity
        let activity = await fetchActivity()

        let totalCost = Decimal(keyInfo.data.usage ?? 0)

        // Aggregate activity by model
        var modelData: [String: (cost: Double, input: Int, output: Int)] = [:]
        for entry in activity {
            let model = entry.model ?? "unknown"
            var current = modelData[model] ?? (0, 0, 0)
            current.cost += entry.totalCost ?? 0
            current.input += entry.promptTokens ?? 0
            current.output += entry.completionTokens ?? 0
            modelData[model] = current
        }

        let breakdown = modelData.map { model, data in
            UsageBreakdown(
                model: model,
                costUSD: Decimal(data.cost),
                inputTokens: data.input,
                outputTokens: data.output,
                cacheReadTokens: 0,
                cacheCreationTokens: 0
            )
        }.sorted { $0.totalTokens > $1.totalTokens }

        let totalInput = modelData.values.reduce(0) { $0 + $1.input }
        let totalOutput = modelData.values.reduce(0) { $0 + $1.output }

        return UsageData(
            provider: name,
            period: period,
            totalCostUSD: totalCost,
            inputTokens: totalInput,
            outputTokens: totalOutput,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            breakdown: breakdown,
            dailyTrend: [],
            fetchedAt: Date()
        )
    }

    func validate() async throws -> Bool {
        guard isConfigured else { throw ProviderError.invalidAPIKey }
        _ = try await fetchKeyInfo()
        return true
    }

    private func fetchKeyInfo() async throws -> OpenRouterKeyResponse {
        guard let url = URL(string: "\(baseURL)/auth/key") else {
            throw ProviderError.apiError("Invalid URL")
        }

        return try await NetworkClient.shared.get(
            url: url,
            headers: headers,
            responseType: OpenRouterKeyResponse.self
        )
    }

    private func fetchActivity() async -> [OpenRouterActivityResponse.OpenRouterActivity] {
        guard let url = URL(string: "\(baseURL)/activity") else { return [] }

        do {
            let response = try await NetworkClient.shared.get(
                url: url,
                headers: headers,
                responseType: OpenRouterActivityResponse.self
            )
            return response.data
        } catch {
            return []
        }
    }
}
