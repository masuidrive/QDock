import Foundation

/// OpenAI Codex CLI usage provider
/// Reads local session history from ~/.codex/history.jsonl
/// Optionally augments with OpenAI Usage API for cost data
///
/// Detection: ~/.codex/ directory
/// Local data: history.jsonl (JSONL session transcripts)
/// API fallback: Uses OpenAI admin key if available (shares with OpenAIProvider)
final class CodexProvider: UsageProvider {
    let id = "codex"
    let name = "Codex CLI"
    let iconName = "apple.terminal"
    let brandColorHex = "#10A37F"
    var isEnabled: Bool = true

    let apiKeyDescription = "No API key needed for local data. Optionally add an OpenAI Admin key for cost tracking."
    let apiKeyPlaceholder = "sk-admin-..."

    private let codexDir: URL

    init() {
        codexDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
    }

    /// Configured if Codex directory exists
    var isConfigured: Bool {
        FileManager.default.fileExists(atPath: codexDir.path)
    }

    /// Check if Codex CLI is installed
    static var isInstalled: Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// Read Codex config
    var config: CodexConfig? {
        CodexConfig.read()
    }

    // MARK: - UsageProvider

    func fetchUsage(for period: UsagePeriod) async throws -> UsageData {
        guard isConfigured else { throw ProviderError.notConfigured }

        // Read local history
        let entries = readHistory(from: period.startDate, to: period.endDate)

        // Aggregate
        var modelData: [String: (input: Int, output: Int, cost: Double, requests: Int)] = [:]

        for entry in entries {
            let model = entry.model ?? "unknown"
            var current = modelData[model] ?? (0, 0, 0, 0)
            current.input += entry.promptTokens ?? 0
            current.output += entry.completionTokens ?? 0
            current.cost += entry.cost ?? 0
            current.requests += 1
            modelData[model] = current
        }

        let totalInput = modelData.values.reduce(0) { $0 + $1.input }
        let totalOutput = modelData.values.reduce(0) { $0 + $1.output }
        var totalCost = Decimal(modelData.values.reduce(0.0) { $0 + $1.cost })

        // If no cost from local data, try OpenAI API
        if totalCost == 0 {
            totalCost = await fetchCostFromOpenAI(period: period)
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

        // Daily trend
        let dailyTrend = buildDailyTrend(from: entries, period: period)

        return UsageData(
            provider: name,
            period: period,
            totalCostUSD: totalCost,
            inputTokens: totalInput,
            outputTokens: totalOutput,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            breakdown: breakdown,
            dailyTrend: dailyTrend,
            fetchedAt: Date()
        )
    }

    func validate() async throws -> Bool {
        return isConfigured
    }

    // MARK: - Local History

    private func readHistory(from startDate: Date, to endDate: Date) -> [CodexHistoryEntry] {
        let historyPath = codexDir.appendingPathComponent("history.jsonl")
        guard let content = try? String(contentsOf: historyPath, encoding: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        var entries: [CodexHistoryEntry] = []

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8) else { continue }

            guard let entry = try? decoder.decode(CodexHistoryEntry.self, from: data) else {
                continue
            }

            // Filter by date
            if let ts = entry.timestamp {
                let date = dateFormatter.date(from: ts) ?? fallbackFormatter.date(from: ts)
                if let date = date {
                    if date < startDate || date > endDate {
                        continue
                    }
                }
            }

            entries.append(entry)
        }

        return entries
    }

    // MARK: - OpenAI API Fallback

    private func fetchCostFromOpenAI(period: UsagePeriod) async -> Decimal {
        // Check if OpenAI admin key is available (shared with OpenAIProvider)
        guard let key = KeychainService.shared.get(key: "openai-api-key"), !key.isEmpty else {
            return 0
        }

        let startTimestamp = Int(period.startDate.timeIntervalSince1970)
        let endTimestamp = Int(period.endDate.timeIntervalSince1970)

        var components = URLComponents(string: "https://api.openai.com/v1/organization/costs")
        components?.queryItems = [
            URLQueryItem(name: "start_time", value: String(startTimestamp)),
            URLQueryItem(name: "end_time", value: String(endTimestamp)),
            URLQueryItem(name: "bucket_width", value: "1d"),
        ]

        guard let url = components?.url else { return 0 }

        let headers = [
            "Authorization": "Bearer \(key)",
            "Content-Type": "application/json",
        ]

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
            return Decimal(total) / 100
        } catch {
            return 0
        }
    }

    // MARK: - Daily Trend

    private func buildDailyTrend(
        from entries: [CodexHistoryEntry],
        period: UsagePeriod
    ) -> [DailyUsage] {
        guard period != .today && period != .yesterday else { return [] }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]

        var dailyData: [String: (input: Int, output: Int, cost: Double)] = [:]

        for entry in entries {
            guard let ts = entry.timestamp,
                  let date = isoFormatter.date(from: ts) ?? fallback.date(from: ts) else {
                continue
            }

            let dayKey = dateFormatter.string(from: date)
            var current = dailyData[dayKey] ?? (0, 0, 0)
            current.input += entry.promptTokens ?? 0
            current.output += entry.completionTokens ?? 0
            current.cost += entry.cost ?? 0
            dailyData[dayKey] = current
        }

        return dailyData.compactMap { dayKey, data in
            guard let date = dateFormatter.date(from: dayKey) else { return nil }
            return DailyUsage(
                date: date,
                costUSD: Decimal(data.cost),
                inputTokens: data.input,
                outputTokens: data.output
            )
        }.sorted { $0.date < $1.date }
    }
}
