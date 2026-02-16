import Foundation

/// Configuration for a usage provider
struct ProviderConfig: Codable, Identifiable, Equatable {
    let id: String
    var displayName: String
    var isEnabled: Bool
    var apiKeyRef: String  // Reference to Keychain item
    var customEndpoint: String?
    var additionalSettings: [String: String]

    static func anthropic() -> ProviderConfig {
        ProviderConfig(
            id: "anthropic",
            displayName: "Anthropic",
            isEnabled: true,
            apiKeyRef: "anthropic-admin-key",
            customEndpoint: nil,
            additionalSettings: [:]
        )
    }

    static func openAI() -> ProviderConfig {
        ProviderConfig(
            id: "openai",
            displayName: "OpenAI",
            isEnabled: false,
            apiKeyRef: "openai-key",
            customEndpoint: nil,
            additionalSettings: [:]
        )
    }

    static func openRouter() -> ProviderConfig {
        ProviderConfig(
            id: "openrouter",
            displayName: "OpenRouter",
            isEnabled: false,
            apiKeyRef: "openrouter-key",
            customEndpoint: nil,
            additionalSettings: [:]
        )
    }
}
