import Foundation

/// Parses Claude Code session JSONL files to compute local token usage.
/// Used as a fallback when the API is rate-limited or unavailable.
final class LocalUsageParser {

    private let claudeDir: URL

    init(claudeDir: URL? = nil) {
        self.claudeDir = claudeDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
    }

    struct TokenUsage {
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheCreationTokens: Int = 0
        var cacheReadTokens: Int = 0
        var messageCount: Int = 0

        var totalTokens: Int {
            inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
        }

        /// Weighted token cost — approximates server-side billing weight.
        /// Output tokens cost ~5x input tokens for Opus.
        var weightedTokens: Int {
            inputTokens + outputTokens * 5 + cacheCreationTokens + cacheReadTokens / 10
        }
    }

    /// Parse all session JSONL files and aggregate token usage within a time window.
    func usage(since cutoff: Date) -> TokenUsage {
        let projectsDir = claudeDir.appendingPathComponent("projects")
        let fm = FileManager.default

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return TokenUsage()
        }

        var total = TokenUsage()
        let cutoffStr = ISO8601DateFormatter().string(from: cutoff)

        for projectDir in projectDirs {
            guard var isDir = try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                  isDir else { continue }

            guard let files = try? fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                // Skip files not modified since cutoff
                if let modDate = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   modDate < cutoff {
                    continue
                }

                let fileUsage = parseJSONLFile(file, cutoffString: cutoffStr)
                total.inputTokens += fileUsage.inputTokens
                total.outputTokens += fileUsage.outputTokens
                total.cacheCreationTokens += fileUsage.cacheCreationTokens
                total.cacheReadTokens += fileUsage.cacheReadTokens
                total.messageCount += fileUsage.messageCount
            }
        }

        return total
    }

    // MARK: - Private

    private func parseJSONLFile(_ url: URL, cutoffString: String) -> TokenUsage {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return TokenUsage()
        }

        var usage = TokenUsage()

        for line in content.components(separatedBy: "\n") where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            // Filter by timestamp
            guard let timestamp = entry["timestamp"] as? String,
                  timestamp >= cutoffString else {
                continue
            }

            // Only assistant messages have usage
            guard entry["type"] as? String == "assistant",
                  let message = entry["message"] as? [String: Any],
                  let usageDict = message["usage"] as? [String: Any] else {
                continue
            }

            usage.inputTokens += usageDict["input_tokens"] as? Int ?? 0
            usage.outputTokens += usageDict["output_tokens"] as? Int ?? 0
            usage.cacheCreationTokens += usageDict["cache_creation_input_tokens"] as? Int ?? 0
            usage.cacheReadTokens += usageDict["cache_read_input_tokens"] as? Int ?? 0
            usage.messageCount += 1
        }

        return usage
    }
}
