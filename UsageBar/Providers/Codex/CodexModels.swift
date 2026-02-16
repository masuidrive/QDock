import Foundation

// MARK: - Codex Local History

/// A single entry from ~/.codex/history.jsonl
struct CodexHistoryEntry: Decodable {
    let sessionId: String?
    let timestamp: String?
    let model: String?
    let provider: String?
    let messages: [CodexMessage]?
    let totalTokens: Int?
    let promptTokens: Int?
    let completionTokens: Int?
    let cost: Double?

    struct CodexMessage: Decodable {
        let role: String?
        let content: String?
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case timestamp
        case model
        case provider
        case messages
        case totalTokens = "total_tokens"
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case cost
    }
}

// MARK: - Codex Config

/// Codex configuration from ~/.codex/config.toml (simplified key-value extraction)
struct CodexConfig {
    let model: String?
    let provider: String?
    let historyPersistence: String?  // "full", "none"

    static func read() -> CodexConfig? {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml")
        guard let content = try? String(contentsOf: configPath, encoding: .utf8) else {
            return nil
        }

        return CodexConfig(
            model: extractTOMLValue(from: content, key: "model"),
            provider: extractTOMLValue(from: content, key: "provider"),
            historyPersistence: extractTOMLValue(from: content, section: "history", key: "persistence")
        )
    }

    private static func extractTOMLValue(from content: String, section: String? = nil, key: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        var inSection = section == nil

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Section header
            if trimmed.hasPrefix("[") {
                let sectionName = trimmed
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    .trimmingCharacters(in: .whitespaces)
                inSection = (section == nil) || (sectionName == section)
                continue
            }

            guard inSection else { continue }

            // Key = "value" or key = 'value'
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let foundKey = parts[0].trimmingCharacters(in: .whitespaces)
            if foundKey == key {
                return parts[1]
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }

        return nil
    }
}
