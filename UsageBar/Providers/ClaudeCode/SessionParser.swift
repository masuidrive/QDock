import Foundation

/// Simplified session parser — only reads config files, no JSONL parsing
final class SessionParser {

    private let claudeDir: URL
    private let decoder: JSONDecoder

    init(claudeDir: URL? = nil) {
        self.claudeDir = claudeDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        self.decoder = JSONDecoder()
    }

    /// Read the global config (~/.claude.json)
    func readGlobalConfig() -> ClaudeGlobalConfig? {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: configPath) else { return nil }
        return try? decoder.decode(ClaudeGlobalConfig.self, from: data)
    }

    /// Check if the projects directory has any session files
    func hasSessionFiles() -> Bool {
        let projectsDir = claudeDir.appendingPathComponent("projects")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        return !contents.isEmpty
    }
}
