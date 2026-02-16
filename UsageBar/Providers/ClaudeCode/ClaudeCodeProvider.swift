import Foundation

/// Claude Code local provider — reads usage directly from local files
/// No API key needed! Automatically detects Claude Code installation and
/// reads session data from ~/.claude/projects/ and stats from stats-cache.json
///
/// Fallback chain:
/// 1. Local JSONL session files (best — full per-session detail)
/// 2. stats-cache.json (good — aggregated model usage with cost)
/// 3. OAuth token → Anthropic API (fallback — org-level usage when no local files)
/// 4. Pricing-based estimation (last resort — calculate cost from token counts)
final class ClaudeCodeProvider: UsageProvider {
    let id = "claude-code-local"
    let name = "Claude Code"
    let iconName = "terminal"
    let brandColorHex = "#D4A574"
    var isEnabled: Bool = true

    let apiKeyDescription = "No API key needed! Reads directly from your local Claude Code data."
    let apiKeyPlaceholder = ""

    private(set) var detector = ClaudeCodeDetector()
    private(set) var detectionResult: ClaudeCodeDetector.DetectionResult?
    private var sessionParser: SessionParser?
    private var cachedSessions: [ClaudeCodeSession] = []

    /// Claude Code is configured if any detection strategy succeeds
    var isConfigured: Bool {
        let result = detector.detect()
        detectionResult = result
        return result.isDetected
    }

    /// Check if Claude Code is installed (static convenience)
    static var isInstalled: Bool {
        ClaudeCodeDetector().detect().isDetected
    }

    /// Get account info from ~/.claude.json
    var accountInfo: ClaudeGlobalConfig.OAuthAccount? {
        getParser()?.readGlobalConfig()?.oauthAccount
    }

    /// Get subscription type
    var subscriptionType: String? {
        ClaudeKeychainReader.subscriptionType
            ?? accountInfo?.subscriptionType
    }

    /// Whether user is logged in (has OAuth creds)
    var isLoggedIn: Bool {
        ClaudeKeychainReader.hasCredentials
    }

    /// Detection strategy that was used
    var activeStrategy: ClaudeCodeDetector.Strategy {
        detectionResult?.strategy ?? .none
    }

    /// Human-readable detection status
    var detectionMessage: String {
        detectionResult?.message ?? "Not detected"
    }

    /// Get recently parsed sessions
    var recentSessions: [ClaudeCodeSession] {
        cachedSessions
    }

    /// Set a custom config directory path
    func setCustomPath(_ path: String) {
        detector.customConfigPath = path.isEmpty ? nil : path
        sessionParser = nil  // Reset parser to pick up new path
    }

    // MARK: - UsageProvider

    func fetchUsage(for period: UsagePeriod) async throws -> UsageData {
        let result = detector.detect()
        detectionResult = result

        guard result.isDetected else {
            throw ProviderError.notConfigured
        }

        // Strategy: try local files first, fall back to API
        if result.hasSessions, let parser = getParser() {
            return try await fetchFromLocalFiles(parser: parser, period: period)
        } else if result.hasOAuthCredentials && OAuthAPIFallback.isAvailable {
            // No local session files but we have OAuth — use API
            return try await fetchFromAPI(period: period)
        } else {
            // Only have config dir but no sessions yet
            throw ProviderError.apiError(
                "Claude Code detected but no session data found yet. "
                + "Start a Claude Code session to see usage data here."
            )
        }
    }

    func validate() async throws -> Bool {
        let result = detector.detect()
        return result.isDetected
    }

    // MARK: - Data Source: Local Files

    private func fetchFromLocalFiles(
        parser: SessionParser,
        period: UsagePeriod
    ) async throws -> UsageData {
        let sessions = parser.sessions(from: period.startDate, to: period.endDate)
        cachedSessions = sessions

        let statsCache = parser.readStatsCache()

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

        // Cost fallback chain
        if totalCost == 0, let modelUsage = statsCache?.modelUsage {
            totalCost = estimateCostFromStats(
                modelUsage: modelUsage,
                inputTokens: totalInput,
                outputTokens: totalOutput,
                cacheReadTokens: totalCacheRead,
                cacheCreationTokens: totalCacheCreation
            )
        }

        if totalCost == 0 {
            totalCost = estimateCostFromPricing(
                inputTokens: totalInput,
                outputTokens: totalOutput,
                cacheReadTokens: totalCacheRead
            )
        }

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

    // MARK: - Data Source: API Fallback

    private func fetchFromAPI(period: UsagePeriod) async throws -> UsageData {
        cachedSessions = []  // No session detail from API
        return try await OAuthAPIFallback.fetchRecentUsage(for: period)
    }

    // MARK: - Cost Estimation

    private func estimateCostFromStats(
        modelUsage: [String: StatsCache.ModelUsageEntry],
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheCreationTokens: Int
    ) -> Double {
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

    private func estimateCostFromPricing(
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int
    ) -> Double {
        // Approximate pricing (Claude Sonnet 4 as default)
        // Input: $3/MTok, Output: $15/MTok, Cache read: $0.30/MTok
        let inputCost = Double(inputTokens) / 1_000_000 * 3.0
        let outputCost = Double(outputTokens) / 1_000_000 * 15.0
        let cacheCost = Double(cacheReadTokens) / 1_000_000 * 0.30
        return inputCost + outputCost + cacheCost
    }

    // MARK: - Helpers

    private func getParser() -> SessionParser? {
        if let parser = sessionParser { return parser }

        let result = detector.detect()
        guard let configDir = result.configDir else { return nil }

        let parser = SessionParser(claudeDir: configDir)
        sessionParser = parser
        return parser
    }

    private func buildDailyTrend(
        from sessions: [ClaudeCodeSession],
        period: UsagePeriod
    ) -> [DailyUsage] {
        guard period != .today && period != .yesterday else { return [] }

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
