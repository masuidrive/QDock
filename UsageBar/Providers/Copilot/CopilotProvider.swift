import Foundation

/// GitHub Copilot usage provider
///
/// Two modes:
/// 1. Organization — Uses GitHub PAT with read:org scope for team metrics
/// 2. Individual — Uses GitHub PAT for personal billing/premium request data
///
/// Auth: GitHub Personal Access Token (classic or fine-grained)
/// API: api.github.com/orgs/{org}/copilot/metrics
final class CopilotProvider: UsageProvider {
    let id = "copilot"
    let name = "GitHub Copilot"
    let iconName = "bolt.fill"
    let brandColorHex = "#6E40C9"
    var isEnabled: Bool = false

    let apiKeyDescription = "Requires a GitHub PAT with read:org and manage_billing:copilot scopes."
    let apiKeyPlaceholder = "ghp_..."

    private let baseURL = "https://api.github.com"
    private let keychainKey = "copilot-api-key"

    /// Organization name (stored in UserDefaults)
    var organizationName: String {
        get { UserDefaults.standard.string(forKey: "copilot-org-name") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "copilot-org-name") }
    }

    /// GitHub username for individual billing
    var username: String {
        get { UserDefaults.standard.string(forKey: "copilot-username") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "copilot-username") }
    }

    var isConfigured: Bool {
        guard let key = KeychainService.shared.get(key: keychainKey) else { return false }
        return !key.isEmpty && (!organizationName.isEmpty || !username.isEmpty)
    }

    private var token: String? {
        KeychainService.shared.get(key: keychainKey)
    }

    private var headers: [String: String] {
        guard let token = token else { return [:] }
        return [
            "Authorization": "Bearer \(token)",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        ]
    }

    // MARK: - UsageProvider

    func fetchUsage(for period: UsagePeriod) async throws -> UsageData {
        guard isConfigured else { throw ProviderError.notConfigured }

        if !organizationName.isEmpty {
            return try await fetchOrgMetrics(period: period)
        } else if !username.isEmpty {
            return try await fetchIndividualUsage(period: period)
        } else {
            throw ProviderError.notConfigured
        }
    }

    func validate() async throws -> Bool {
        guard let token = token, !token.isEmpty else {
            throw ProviderError.invalidAPIKey
        }

        // Try to verify the token with a simple API call
        guard let url = URL(string: "\(baseURL)/user") else {
            return false
        }

        _ = try await NetworkClient.shared.get(
            url: url,
            headers: headers,
            responseType: GitHubUser.self
        )
        return true
    }

    // MARK: - Organization Metrics

    private func fetchOrgMetrics(period: UsagePeriod) async throws -> UsageData {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let since = dateFormatter.string(from: period.startDate)
        let until = dateFormatter.string(from: period.endDate)

        var components = URLComponents(string: "\(baseURL)/orgs/\(organizationName)/copilot/metrics")!
        components.queryItems = [
            URLQueryItem(name: "since", value: since),
            URLQueryItem(name: "until", value: until),
        ]

        let days = try await NetworkClient.shared.get(
            url: components.url!,
            headers: headers,
            responseType: [CopilotMetricsDay].self
        )

        // Aggregate across all days
        var totalSuggestions = 0
        var totalAcceptances = 0
        var totalLinesSuggested = 0
        var totalLinesAccepted = 0
        var totalChats = 0
        var modelData: [String: (suggestions: Int, acceptances: Int, linesSuggested: Int, linesAccepted: Int)] = [:]
        var dailyTrend: [DailyUsage] = []

        for day in days {
            var daySuggestions = 0
            var dayAcceptances = 0

            // Process code completions
            if let completions = day.copilotIdeCodeCompletions {
                for editor in completions.editors ?? [] {
                    for model in editor.models ?? [] {
                        let modelName = model.name ?? "default"
                        var current = modelData[modelName] ?? (0, 0, 0, 0)

                        for lang in model.languages ?? [] {
                            let suggestions = lang.totalCodeSuggestions ?? 0
                            let acceptances = lang.totalCodeAcceptances ?? 0
                            let linesSug = lang.totalCodeLinesSuggested ?? 0
                            let linesAcc = lang.totalCodeLinesAccepted ?? 0

                            current.suggestions += suggestions
                            current.acceptances += acceptances
                            current.linesSuggested += linesSug
                            current.linesAccepted += linesAcc

                            daySuggestions += suggestions
                            dayAcceptances += acceptances
                            totalLinesSuggested += linesSug
                            totalLinesAccepted += linesAcc
                        }

                        modelData[modelName] = current
                    }
                }
            }

            // Chat metrics
            totalChats += day.copilotIdeChat?.totalChats ?? 0
            totalChats += day.copilotDotcomChat?.totalChats ?? 0

            totalSuggestions += daySuggestions
            totalAcceptances += dayAcceptances

            // Daily trend
            if let dateStr = day.date, let date = dateFormatter.date(from: dateStr) {
                dailyTrend.append(DailyUsage(
                    date: date,
                    costUSD: 0,
                    inputTokens: daySuggestions,
                    outputTokens: dayAcceptances
                ))
            }
        }

        // Build breakdown
        var breakdown = modelData.map { model, data in
            UsageBreakdown(
                model: model,
                costUSD: 0,
                inputTokens: data.suggestions,
                outputTokens: data.acceptances,
                cacheReadTokens: data.linesSuggested,
                cacheCreationTokens: data.linesAccepted
            )
        }.sorted { $0.totalTokens > $1.totalTokens }

        // Add chat as a separate item
        if totalChats > 0 {
            breakdown.append(UsageBreakdown(
                model: "Copilot Chat",
                costUSD: 0,
                inputTokens: totalChats,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheCreationTokens: 0
            ))
        }

        return UsageData(
            provider: name,
            period: period,
            totalCostUSD: 0,  // Copilot is subscription-based, no per-token cost
            inputTokens: totalSuggestions,
            outputTokens: totalAcceptances,
            cacheReadTokens: totalLinesSuggested,
            cacheCreationTokens: totalLinesAccepted,
            breakdown: breakdown,
            dailyTrend: dailyTrend.sorted { $0.date < $1.date },
            fetchedAt: Date()
        )
    }

    // MARK: - Individual Usage

    private func fetchIndividualUsage(period: UsagePeriod) async throws -> UsageData {
        guard let url = URL(string: "\(baseURL)/users/\(username)/settings/billing/premium_request/usage") else {
            throw ProviderError.apiError("Invalid username")
        }

        let billing = try await NetworkClient.shared.get(
            url: url,
            headers: headers,
            responseType: CopilotBillingUsage.self
        )

        let used = billing.premiumRequestsUsed ?? 0
        let included = billing.premiumRequestsIncluded ?? 0

        let breakdown = [
            UsageBreakdown(
                model: "Premium Requests",
                costUSD: 0,
                inputTokens: used,
                outputTokens: included - used,
                cacheReadTokens: 0,
                cacheCreationTokens: 0
            ),
        ]

        return UsageData(
            provider: name,
            period: period,
            totalCostUSD: 0,
            inputTokens: used,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            breakdown: breakdown,
            dailyTrend: [],
            fetchedAt: Date()
        )
    }
}

// MARK: - Helper Models

/// Minimal GitHub user response for token validation
private struct GitHubUser: Decodable {
    let login: String?
    let id: Int?
}
