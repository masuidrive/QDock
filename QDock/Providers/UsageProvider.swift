import Foundation

/// Protocol that all quota providers must conform to
protocol QuotaProvider: AnyObject {
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

    /// Whether the provider has valid configuration
    var isConfigured: Bool { get }

    /// Current authentication status
    var authStatus: AuthStatus { get }

    /// Refresh local provider state (detection, auth snapshot, account metadata)
    func refreshLocalState() async

    /// Fetch quota data (windows are server-defined, no period parameter)
    func fetchQuota() async throws -> QuotaData

    /// Validate the current configuration
    func validate() async throws -> Bool
}

// MARK: - AuthStatus

/// Authentication state for a provider
enum AuthStatus {
    case authenticated(email: String?)
    case needsAuth(message: String)
    case notInstalled(message: String)

    var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }

    var statusMessage: String {
        switch self {
        case .authenticated(let email):
            if let email = email {
                return "Authenticated (\(email))"
            }
            return "Authenticated"
        case .needsAuth(let message):
            return message
        case .notInstalled(let message):
            return message
        }
    }
}

// MARK: - ProviderError

/// Errors that providers can throw
enum ProviderError: LocalizedError {
    case notConfigured
    case notInstalled
    case authRequired(String)
    case tokenExpired
    case rateLimited(retryAfterSeconds: Double? = nil)
    case networkError(Error)
    case apiError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Provider is not configured."
        case .notInstalled:
            return "Application not installed."
        case .authRequired(let message):
            return message
        case .tokenExpired:
            return "Authentication token has expired. Please re-authenticate."
        case .rateLimited(let retryAfterSeconds):
            if let seconds = retryAfterSeconds, seconds > 0 {
                let minutes = max(1, Int((seconds / 60).rounded(.up)))
                return "Rate limited by the API. Retrying in ~\(minutes)m."
            }
            return "Rate limited. Please wait a moment and try again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let message):
            return message
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}

extension QuotaProvider {
    func refreshLocalState() async {}
}
