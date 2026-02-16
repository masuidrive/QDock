import Foundation

/// Claude Code local provider — reads usage directly from local files
/// No API key needed! Automatically detects Claude Code installation and
/// reads session data from ~/.claude/projects/ and stats from stats-cache.json
final class ClaudeCodeProvider: UsageProvider {
    let id = "claude-code-local"
    let name = "Claude Code"
    let iconName = "terminal"
    let brandColorHex = "#D4A574"  // Anthropic brand color
    var isEnabled: Bool = true

    let apiKeyDescription = "No API key needed! Reads directly from your local Claude Code data."
    let apiKeyPlaceholder = ""

    private let sessionParser = SessionParser()
    private var cachedSessions: [ClaudeCodeSession] = []

    /// Claude Code is configured if ~/.claude/ exists
    var isConfigured: Bool {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        return FileManager.default.fileExists(atPath: claudeDir.path)
    }

    /// Check if Claude Code is installed
    static var isInstalled: Bool {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        return FileManager.default.fileExists(atPath: claudeDir.path)
    }

    /// Get account info from ~/.claude.json
    var accountInfo: ClaudeGlobalConfig.OAuthAccount? {
        sessionParser.readGlobalConfig()?.oauthAccount
    }

    /// Get subscription type from Keychain
    var subscriptionType: String? {
        ClaudeKeychainReader.subscriptionType
            ?? accountInfo?.subscriptionType
    }

    /// Whether user is logged in (has OAuth creds)
    var isLoggedIn: Bool {
        ClaudeKeychainReader.hasCredentials
    }

    /// Get recently parsed sessions
    var recentSessions: [ClaudeCodeSession] {
        cachedSessions
    }

    // MARK: - UsageProvider

    func fetchUsage(for period: UsagePeriod) async throws -> UsageData {
        guard isConfigured else { throw ProviderError.notConfigured }

        // Parse sessions for the period
        let sessions = sessionParser.sessions(from: period.startDate, to: period.endDate)
        cachedSessions = sessions

        // Also read stats cache for cost data
        let statsCache = sessionParser.readStatsCache()

        // Aggregate session data
        var totalInput = 0
        var totalOutput = 0
        var totalCacheRead = 0
        var totalCacheCreation = 0
        var totalCost: Double = 0
        var modelData: [String: (input: Int, output: Int, cacheRead: Int, cacheCreation: Int, cost: Double)] = [:]

        for session in sessions {
            totalInput += session.totalInputTokens
            totalOutput += session.totalOutputTokens
            totalCacheRead += session.totalCacheReadTokens
            totalCacheCreation += session.totalCacheCreationTokens
            totalCost += session.costUSD

            for model in session.models {
                var current = modelData[model] ?? (0, 0, 0, 0, 0)
                // Distribute session tokens proportionally if multiple models
                // For simplicity, assign all to the primary model
                if model == session.model {
                    current.input += session.totalInputTokens
                    current.output += session.totalOutputTokens
                    current.cacheRead += session.totalCacheReadTokens
                    current.cacheCreation += session.totalCacheCreationTokens
                    current.cost += session.costUSD
                }
                modelData[model] = current
            }
        }

        // If no cost from sessions, try stats cache for cost estimation
        if totalCost == 0, let modelUsage = statsCache?.modelUsage {
            totalCost = estimateCostFromStats(
                modelUsage: modelUsage,
                inputTokens: totalInput,
                outputTokens: totalOutput,
                cacheReadTokens: totalCacheRead,
                cacheCreationTokens: totalCacheCreation
            )
        }

        // Build breakdown
        let breakdown = modelData.map { model, data in
            UsageBreakdown(
                model: model,
                costUSD: Decimal(data.cost),
                inputTokens: data.input,
                outputTokens: data.output,
                cacheReadTokens: data.cacheRead,
                cacheCreationTokens: data.cacheCreation
            )
        }.sorted { $0.totalTokens > $1.totalTokens }

        // Build daily trend
        let dailyTrend = buildDailyTrend(from: sessions, period: period)

        return UsageData(
            provider: name,
            period: period,
            totalCostUSD: Decimal(totalCost),
            inputTokens: totalInput,
            outputTokens: totalOutput,
            cacheReadTokens: totalCacheRead,
            cacheCreationTokens: totalCacheCreation,
            breakdown: breakdown,
            dailyTrend: dailyTrend,
            fetchedAt: Date()
        )
    }

    func validate() async throws -> Bool {
        return isConfigured
    }

    // MARK: - Cost Estimation

    /// Estimate cost based on model pricing when session cost data isn't available
    private func estimateCostFromStats(
        modelUsage: [String: StatsCache.ModelUsageEntry],
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheCreationTokens: Int
    ) -> Double {
        // Use stats cache to determine average cost per token
        var totalStatsTokens = 0
        var totalStatsCost: Double = 0

        for (_, usage) in modelUsage {
            let tokens = (usage.inputTokens ?? 0) + (usage.outputTokens ?? 0)
                + (usage.cacheReadInputTokens ?? 0) + (usage.cacheCreationInputTokens ?? 0)
            totalStatsTokens += tokens
            totalStatsCost += usage.costUSD ?? 0
        }

        guard totalStatsTokens > 0 else {
            return estimateCostFromPricing(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheReadTokens: cacheReadTokens
            )
        }

        let avgCostPerToken = totalStatsCost / Double(totalStatsTokens)
        let totalTokens = inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
        return avgCostPerToken * Double(totalTokens)
    }

    /// Fallback: estimate cost using known Claude pricing
    private func estimateCostFromPricing(
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int
    ) -> Double {
        // Approximate pricing (Claude Sonnet as default)
        // Input: $3/MTok, Output: $15/MTok, Cache read: $0.30/MTok
        let inputCost = Double(inputTokens) / 1_000_000 * 3.0
        let outputCost = Double(outputTokens) / 1_000_000 * 15.0
        let cacheCost = Double(cacheReadTokens) / 1_000_000 * 0.30
        return inputCost + outputCost + cacheCost
    }

    // MARK: - Daily Trend

    private func buildDailyTrend(
        from sessions: [ClaudeCodeSession],
        period: UsagePeriod
    ) -> [DailyUsage] {
        guard period != .today && period != .yesterday else { return [] }

        let calendar = Calendar.current
        var dailyData: [String: (input: Int, output: Int, cost: Double)] = [:]

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for session in sessions {
            guard let startTime = session.startTime else { continue }
            let dayKey = dateFormatter.string(from: startTime)
            var current = dailyData[dayKey] ?? (0, 0, 0)
            current.input += session.totalInputTokens
            current.output += session.totalOutputTokens
            current.cost += session.costUSD
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
