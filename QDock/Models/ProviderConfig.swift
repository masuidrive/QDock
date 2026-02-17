import Foundation

/// Simplified configuration for a quota provider
struct ProviderConfig: Codable, Identifiable, Equatable {
    let id: String
    var displayName: String
    var isEnabled: Bool

    static func claudeCode() -> ProviderConfig {
        ProviderConfig(
            id: "claude-code",
            displayName: "Claude Code",
            isEnabled: true
        )
    }

    static func codex() -> ProviderConfig {
        ProviderConfig(
            id: "codex",
            displayName: "Codex CLI",
            isEnabled: true
        )
    }
}
