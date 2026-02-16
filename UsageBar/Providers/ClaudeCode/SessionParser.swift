import Foundation

/// Parses Claude Code session JSONL files from ~/.claude/projects/
final class SessionParser {

    private let claudeDir: URL
    private let decoder: JSONDecoder

    init(claudeDir: URL? = nil) {
        self.claudeDir = claudeDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        self.decoder = JSONDecoder()
    }

    // MARK: - Public API

    /// Get all sessions within a date range
    func sessions(from startDate: Date, to endDate: Date) -> [ClaudeCodeSession] {
        let projectDirs = listProjectDirectories()
        var allSessions: [ClaudeCodeSession] = []

        for projectDir in projectDirs {
            let sessions = parseSessionsInDirectory(projectDir, from: startDate, to: endDate)
            allSessions.append(contentsOf: sessions)
        }

        return allSessions.sorted { ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast) }
    }

    /// Get sessions for today
    func todaySessions() -> [ClaudeCodeSession] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        return sessions(from: startOfToday, to: endOfToday)
    }

    /// Get all active session IDs (sessions modified in last hour)
    func activeSessions() -> [ClaudeCodeSession] {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        return sessions(from: oneHourAgo, to: Date())
    }

    // MARK: - Stats Cache

    /// Read the stats-cache.json file
    func readStatsCache() -> StatsCache? {
        let statsPath = claudeDir.appendingPathComponent("stats-cache.json")
        guard let data = try? Data(contentsOf: statsPath) else { return nil }
        return try? decoder.decode(StatsCache.self, from: data)
    }

    /// Read the global config (~/.claude.json)
    func readGlobalConfig() -> ClaudeGlobalConfig? {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: configPath) else { return nil }
        return try? decoder.decode(ClaudeGlobalConfig.self, from: data)
    }

    // MARK: - Private Helpers

    private func listProjectDirectories() -> [URL] {
        let projectsDir = claudeDir.appendingPathComponent("projects")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.filter { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }
    }

    private func parseSessionsInDirectory(
        _ dir: URL,
        from startDate: Date,
        to endDate: Date
    ) -> [ClaudeCodeSession] {
        let projectPath = decodeProjectPath(dir.lastPathComponent)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let jsonlFiles = files.filter { $0.pathExtension == "jsonl" }

        // Filter by modification date for performance
        let relevantFiles = jsonlFiles.filter { file in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                  let modDate = attrs[.modificationDate] as? Date else {
                return false
            }
            // Include files modified within our date range (with some buffer)
            return modDate >= startDate.addingTimeInterval(-86400)
        }

        return relevantFiles.compactMap { file in
            parseSession(at: file, projectPath: projectPath, from: startDate, to: endDate)
        }
    }

    private func parseSession(
        at url: URL,
        projectPath: String,
        from startDate: Date,
        to endDate: Date
    ) -> ClaudeCodeSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let content = String(data: data, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        let sessionId = url.deletingPathExtension().lastPathComponent
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let altDateFormatter = ISO8601DateFormatter()
        altDateFormatter.formatOptions = [.withInternetDateTime]

        var firstTimestamp: Date?
        var lastTimestamp: Date?
        var messageCount = 0
        var totalInput = 0
        var totalOutput = 0
        var totalCacheRead = 0
        var totalCacheCreation = 0
        var totalCost: Double = 0
        var models = Set<String>()
        var primaryModel: String?
        var gitBranch: String?

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let msg = try? decoder.decode(SessionMessage.self, from: lineData) else {
                continue
            }

            // Parse timestamp
            if let ts = msg.timestamp {
                let date = dateFormatter.date(from: ts) ?? altDateFormatter.date(from: ts)
                if let date = date {
                    if firstTimestamp == nil { firstTimestamp = date }
                    lastTimestamp = date
                }
            }

            // Track git branch
            if gitBranch == nil, let branch = msg.gitBranch {
                gitBranch = branch
            }

            // Process assistant messages with usage data
            if msg.type == "assistant", let usage = msg.message?.usage {
                messageCount += 1
                totalInput += usage.inputTokens ?? 0
                totalOutput += usage.outputTokens ?? 0
                totalCacheRead += usage.cacheReadInputTokens ?? 0
                totalCacheCreation += usage.cacheCreationInputTokens
                    ?? usage.cacheCreation?.totalTokens ?? 0

                if let model = msg.message?.model ?? msg.model {
                    models.insert(model)
                    if primaryModel == nil { primaryModel = model }
                }
            }

            // Track cost
            if let cost = msg.costUSD {
                totalCost += cost
            }
        }

        // Check if session falls within date range
        if let first = firstTimestamp, first > endDate { return nil }
        if let last = lastTimestamp, last < startDate { return nil }

        // Skip empty sessions
        guard messageCount > 0 else { return nil }

        return ClaudeCodeSession(
            id: sessionId,
            projectPath: projectPath,
            startTime: firstTimestamp,
            endTime: lastTimestamp,
            messageCount: messageCount,
            model: primaryModel,
            gitBranch: gitBranch,
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            totalCacheReadTokens: totalCacheRead,
            totalCacheCreationTokens: totalCacheCreation,
            costUSD: totalCost,
            models: models
        )
    }

    /// Decode project path from directory name
    /// ~/.claude/projects/ encodes paths by replacing "/" with "-"
    private func decodeProjectPath(_ encoded: String) -> String {
        // The encoding replaces "/" with "-"
        // e.g., "-Users-sean-myproject" → "/Users/sean/myproject"
        var path = encoded
        // First char is always "-" representing "/"
        if path.hasPrefix("-") {
            path = "/" + String(path.dropFirst())
        }
        path = path.replacingOccurrences(of: "-", with: "/")
        return path
    }
}
