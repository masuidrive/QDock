import Foundation
import Security

/// Reads Claude Code OAuth credentials from macOS Keychain
final class ClaudeKeychainReader {

    /// Service names used by Claude Code in Keychain
    private static let serviceNames = [
        "Claude Code-credentials",
        "Claude Code",
    ]

    /// Attempt to read OAuth credentials from Keychain
    static func readCredentials() -> ClaudeOAuthCredentials? {
        for serviceName in serviceNames {
            if let creds = readFromKeychain(service: serviceName) {
                return creds
            }
        }
        return nil
    }

    /// Check if Claude Code credentials exist in Keychain
    static var hasCredentials: Bool {
        readCredentials() != nil
    }

    /// Get the access token (if valid and not expired)
    static var accessToken: String? {
        guard let creds = readCredentials(),
              let oauth = creds.claudeAiOauth,
              !oauth.isExpired,
              let token = oauth.accessToken else {
            return nil
        }
        return token
    }

    /// Get subscription type (max, pro, etc.)
    static var subscriptionType: String? {
        readCredentials()?.claudeAiOauth?.subscriptionType
    }

    // MARK: - Private

    private static func readFromKeychain(service: String) -> ClaudeOAuthCredentials? {
        let username = ProcessInfo.processInfo.environment["USER"]
            ?? NSUserName()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        // The credential is stored as JSON
        let decoder = JSONDecoder()
        return try? decoder.decode(ClaudeOAuthCredentials.self, from: data)
    }
}
