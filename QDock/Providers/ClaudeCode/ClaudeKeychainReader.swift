import Foundation

/// Reads Claude Code OAuth credentials — uses `security` CLI to NEVER trigger a password dialog.
///
/// Why CLI instead of Security framework?
/// - `SecItemCopyMatching` triggers macOS "allow access" dialog for another app's keychain items
/// - `/usr/bin/security find-generic-password` reads from the login keychain without prompting
///   because the login keychain is already unlocked while the user is logged in
/// - This is how claude-meter and similar apps avoid the password prompt
final class ClaudeKeychainReader {

    /// Service name used by Claude Code in Keychain
    private static let serviceName = "Claude Code-credentials"

    /// Cache to avoid repeated shell calls
    private static var cachedCredentials: ClaudeOAuthCredentials?
    private static var lastCacheTime: Date?
    private static let cacheTTL: TimeInterval = 300 // 5 minutes

    /// Attempt to read OAuth credentials — NEVER prompts for password
    static func readCredentials() -> ClaudeOAuthCredentials? {
        // Return cached if fresh
        if let cached = cachedCredentials,
           let cacheTime = lastCacheTime,
           Date().timeIntervalSince(cacheTime) < cacheTTL {
            return cached
        }

        guard let data = readViaSecurityCLI() else {
            return nil
        }

        let decoder = JSONDecoder()

        // Try wrapped format: { "claudeAiOauth": { ... } }
        if let creds = try? decoder.decode(ClaudeOAuthCredentials.self, from: data) {
            cachedCredentials = creds
            lastCacheTime = Date()
            return creds
        }

        // Try direct format: { "accessToken": ..., "refreshToken": ... }
        if let oauth = try? decoder.decode(ClaudeOAuthCredentials.OAuthData.self, from: data) {
            let creds = ClaudeOAuthCredentials(claudeAiOauth: oauth, primaryApiKey: nil)
            cachedCredentials = creds
            lastCacheTime = Date()
            return creds
        }

        return nil
    }

    /// Clear the cache
    static func clearCache() {
        cachedCredentials = nil
        lastCacheTime = nil
    }

    /// Check if Claude Code credentials exist — NEVER prompts
    static var hasCredentials: Bool {
        readCredentials() != nil
    }

    /// Get the access token (if valid and not expired) — NEVER prompts
    static var accessToken: String? {
        guard let creds = readCredentials(),
              let oauth = creds.claudeAiOauth,
              !oauth.isExpired,
              let token = oauth.accessToken else {
            return nil
        }
        return token
    }

    /// Get subscription type (max, pro, etc.) — NEVER prompts
    static var subscriptionType: String? {
        readCredentials()?.claudeAiOauth?.subscriptionType
    }

    /// OAuth scopes granted to the stored token — NEVER prompts.
    /// The usage endpoint requires `user:profile`; tokens minted by
    /// `claude setup-token` lack it and get rejected.
    static var tokenScopes: [String]? {
        readCredentials()?.claudeAiOauth?.scopes
    }

    // MARK: - Private: Shell-based Keychain Access

    /// Read credentials using `/usr/bin/security` CLI — NO password prompt.
    /// This works because:
    /// - The login keychain is unlocked while the user is logged in
    /// - The `security` CLI tool has implicit access to the login keychain
    /// - Unlike SecItemCopyMatching, it doesn't check per-app ACLs
    ///
    /// Includes a 3-second timeout to prevent blocking the main thread if
    /// the keychain is locked or the system is under load.
    private static func readViaSecurityCLI() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", serviceName, "-w"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        // Wait with timeout to avoid indefinite blocking
        let semaphore = DispatchSemaphore(value: 0)
        var outputData = Data()

        DispatchQueue.global(qos: .utility).async {
            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            semaphore.signal()
        }

        let timeoutResult = semaphore.wait(timeout: .now() + 3.0)
        if timeoutResult == .timedOut {
            process.terminate()
            return nil
        }

        guard process.terminationStatus == 0, !outputData.isEmpty else {
            return nil
        }

        // Remove trailing newline
        if let string = String(data: outputData, encoding: .utf8) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.data(using: .utf8)
        }

        return outputData
    }
}
