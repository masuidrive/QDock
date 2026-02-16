import Foundation

/// Protocol that all usage providers must conform to
protocol UsageProvider: AnyObject {
    /// Unique identifier for this provider
    var id: String { get }

    /// Display name shown in the UI
    var name: String { get }

    /// SF Symbol name for the provider icon
    var iconName: String { get }

    /// Color hex for branding
    var brandColorHex: String { get }

    /// Whether the provider is currently enabled
    var isEnabled: Bool { get set }

    /// Whether the provider has valid configuration (API key set)
    var isConfigured: Bool { get }

    /// Description of what API key is needed
    var apiKeyDescription: String { get }

    /// Placeholder text for the API key input field
    var apiKeyPlaceholder: String { get }

    /// Fetch usage data for a given time period
    func fetchUsage(for period: UsagePeriod) async throws -> UsageData

    /// Validate the current API key
    func validate() async throws -> Bool
}

/// Errors that providers can throw
enum ProviderError: LocalizedError {
    case notConfigured
    case invalidAPIKey
    case rateLimited
    case networkError(Error)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Provider is not configured. Please add your API key."
        case .invalidAPIKey:
            return "Invalid API key. Please check your key and try again."
        case .rateLimited:
            return "Rate limited. Please wait a moment and try again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let message):
            return message
        }
    }
}
