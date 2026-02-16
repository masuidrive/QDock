import Foundation

/// Windsurf (Codeium) usage provider
///
/// Two modes:
/// 1. Enterprise — Uses service key with Codeium Analytics API
/// 2. Individual — Detects local installation, shows credit usage
///
/// Detection: ~/.codeium/windsurf/ directory
/// Enterprise API: server.codeium.com/api/v1/Analytics (requires service key)
final class WindsurfProvider: UsageProvider {
    let id = "windsurf"
    let name = "Windsurf"
    let iconName = "wind"
    let brandColorHex = "#09B6A2"
    var isEnabled: Bool = false

    let apiKeyDescription = "Enterprise: Enter your Codeium service key for detailed analytics. Individual: auto-detects local installation."
    let apiKeyPlaceholder = "codeium-service-key-..."

    private let enterpriseBaseURL = "https://server.codeium.com/api/v1"
    private let keychainKey = "windsurf-api-key"

    private var codeiumDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codeium")
    }

    private var windsurfDir: URL {
        codeiumDir.appendingPathComponent("windsurf")
    }

    /// Configured if installed locally OR has enterprise key
    var isConfigured: Bool {
        isInstalled || hasServiceKey
    }

    /// Whether Windsurf is installed locally
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: windsurfDir.path)
            || FileManager.default.fileExists(atPath: codeiumDir.path)
    }

    /// Static convenience
    static var isInstalled: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return FileManager.default.fileExists(atPath: home.appendingPathComponent(".codeium/windsurf").path)
            || FileManager.default.fileExists(atPath: home.appendingPathComponent(".codeium").path)
    }

    /// Whether an enterprise service key is configured
    var hasServiceKey: Bool {
        guard let key = KeychainService.shared.get(key: keychainKey) else { return false }
        return !key.isEmpty
    }

    // MARK: - UsageProvider

    func fetchUsage(for period: UsagePeriod) async throws -> UsageData {
        if hasServiceKey {
            return try await fetchEnterpriseUsage(period: period)
        } else if isInstalled {
            return localOnlyUsage(period: period)
        } else {
            throw ProviderError.notConfigured
        }
    }

    func validate() async throws -> Bool {
        if hasServiceKey {
            // Try an API call with the service key
            _ = try await fetchEnterpriseUsage(period: .today)
            return true
        }
        return isInstalled
    }

    // MARK: - Enterprise API

    private func fetchEnterpriseUsage(period: UsagePeriod) async throws -> UsageData {
        guard let serviceKey = KeychainService.shared.get(key: keychainKey) else {
            throw ProviderError.notConfigured
        }

        let formatter = ISO8601DateFormatter()

        // Build analytics request body
        let requestBody: [String: Any] = [
            "service_key": serviceKey,
            "query_data_source": "QUERY_DATA_SOURCE_USER_DATA",
            "query_fields": [
                ["field": "num_acceptances", "aggregation": "QUERY_AGGREGATION_SUM"],
                ["field": "num_lines_accepted", "aggregation": "QUERY_AGGREGATION_SUM"],
            ],
            "filters": [
                ["field": "timestamp", "operator": "QUERY_FILTER_GE", "value": formatter.string(from: period.startDate)],
                ["field": "timestamp", "operator": "QUERY_FILTER_LE", "value": formatter.string(from: period.endDate)],
            ],
        ]

        guard let url = URL(string: "\(enterpriseBaseURL)/Analytics") else {
            throw ProviderError.apiError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ProviderError.apiError("Windsurf API returned \(statusCode)")
        }

        let analyticsResponse = try JSONDecoder().decode(WindsurfAnalyticsResponse.self, from: data)

        // Aggregate
        var totalAcceptances = 0
        var totalLinesAccepted = 0

        for row in analyticsResponse.data ?? [] {
            totalAcceptances += row.numAcceptances ?? 0
            totalLinesAccepted += row.numLinesAccepted ?? 0
        }

        // Also fetch Cascade analytics
        let cascadeData = await fetchCascadeAnalytics(
            serviceKey: serviceKey,
            period: period
        )

        let totalLines = totalLinesAccepted + (cascadeData?.totalLinesAccepted ?? 0)
        let totalToolCalls = cascadeData?.totalToolCalls ?? 0

        let breakdown = [
            UsageBreakdown(
                model: "Autocomplete",
                costUSD: 0,
                inputTokens: totalAcceptances,
                outputTokens: totalLinesAccepted,
                cacheReadTokens: 0,
                cacheCreationTokens: 0
            ),
            UsageBreakdown(
                model: "Cascade (Agent)",
                costUSD: 0,
                inputTokens: totalToolCalls,
                outputTokens: cascadeData?.totalLinesAccepted ?? 0,
                cacheReadTokens: 0,
                cacheCreationTokens: 0
            ),
        ].filter { $0.totalTokens > 0 }

        return UsageData(
            provider: name,
            period: period,
            totalCostUSD: 0,  // Windsurf uses credit-based pricing, no direct $ mapping
            inputTokens: totalAcceptances + totalToolCalls,
            outputTokens: totalLines,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            breakdown: breakdown,
            dailyTrend: cascadeData?.dailyTrend ?? [],
            fetchedAt: Date()
        )
    }

    // MARK: - Cascade Analytics

    private struct CascadeAggregated {
        var totalLinesAccepted: Int
        var totalToolCalls: Int
        var dailyTrend: [DailyUsage]
    }

    private func fetchCascadeAnalytics(
        serviceKey: String,
        period: UsagePeriod
    ) async -> CascadeAggregated? {
        let formatter = ISO8601DateFormatter()

        let requestBody: [String: Any] = [
            "service_key": serviceKey,
            "start_timestamp": formatter.string(from: period.startDate),
            "end_timestamp": formatter.string(from: period.endDate),
        ]

        guard let url = URL(string: "\(enterpriseBaseURL)/CascadeAnalytics") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(WindsurfCascadeResponse.self, from: data)

            var totalLines = 0
            var totalTools = 0
            var trend: [DailyUsage] = []

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            for entry in response.data ?? [] {
                totalLines += entry.linesAccepted ?? 0
                totalTools += entry.toolCalls ?? 0

                if let dateStr = entry.date, let date = dateFormatter.date(from: dateStr) {
                    trend.append(DailyUsage(
                        date: date,
                        costUSD: 0,
                        inputTokens: entry.toolCalls ?? 0,
                        outputTokens: entry.linesAccepted ?? 0
                    ))
                }
            }

            return CascadeAggregated(
                totalLinesAccepted: totalLines,
                totalToolCalls: totalTools,
                dailyTrend: trend.sorted { $0.date < $1.date }
            )
        } catch {
            return nil
        }
    }

    // MARK: - Local-Only Mode

    private func localOnlyUsage(period: UsagePeriod) -> UsageData {
        // Without enterprise API, we can only confirm installation
        // No local usage files are available for Windsurf
        UsageData(
            provider: name,
            period: period,
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
