import Foundation

/// Claude Code quota provider — fetches usage limits from Claude API
///
/// Auth chain (avoids Keychain prompts):
/// 1. ~/.claude/.credentials.json file
/// 2. Keychain (silent read — no prompt if accessible)
/// 3. In-app onboarding fallback
///
/// Data source:
/// - Primary: GET https://api.claude.ai/api/auth/usage
/// - Fallback: cached stale data on failure
final class ClaudeCodeProvider: QuotaProvider {
    let id = "claude-code"
    let name = "Claude"
    let iconName = "terminal"
    let brandColorHex = "#D4A574"
    var isEnabled: Bool = false

    private(set) var detector = ClaudeCodeDetector()
    var detectionResult: ClaudeCodeDetector.DetectionResult? {
        withState { localState.detectionResult }
    }
    private var cachedQuota: QuotaData?
    private var manualToken: String?
    private var localState = ClaudeProviderLocalState.empty
    private let localStateTTL: TimeInterval = 30
    private let stateLock = NSLock()
    private let refreshLock = NSLock()
    private let tokenRefreshLock = NSLock()
    private var isRefreshingToken = false
    private let tokenRefresher = ClaudeTokenRefresher()

    init() {
        if let saved = KeychainService.shared.get(key: "claude-token"), !saved.isEmpty {
            withState {
                manualToken = saved
            }
        }
        refreshLocalStateSync(force: true)
    }

    // MARK: - QuotaProvider

    var isConfigured: Bool {
        refreshLocalStateSync()
        return withState { localState.detectionResult.isDetected }
    }

    var authStatus: AuthStatus {
        refreshLocalStateSync()
        let result = withState { localState.detectionResult }

        guard result.isDetected else {
            return .notInstalled(message: "Claude not detected. Install it via npm or brew.")
        }

        let snapshot = withState { localState }
        if let token = snapshot.accessToken, !token.isEmpty {
            return .authenticated(email: snapshot.accountEmail)
        }

        return .needsAuth(message: "Run `claude` in your terminal to authenticate, or paste your token in Settings.")
    }

    func refreshLocalState() async {
        refreshLocalStateSync(force: true)
    }

    func fetchQuota() async throws -> QuotaData {
        await refreshLocalState()
        let result = withState { localState.detectionResult }

        guard result.isDetected else {
            throw ProviderError.notInstalled
        }

        guard let token = withState({ localState.accessToken }) else {
            throw ProviderError.authRequired(
                "No access token found. Run `claude` in your terminal to authenticate."
            )
        }

        do {
            let quota = try await fetchFromAPI(token: token)
            withState {
                cachedQuota = quota
            }
            return quota
        } catch let error as NetworkError {
            // On 429, try refreshing the token and retrying once
            if case .httpError(let statusCode, _) = error, statusCode == 429 {
                if let newToken = await tryRefreshToken() {
                    do {
                        let quota = try await fetchFromAPI(token: newToken)
                        withState { cachedQuota = quota }
                        return quota
                    } catch {
                        // Retry also failed — fall through to stale cache
                    }
                }
                // Refresh failed or retry failed — return stale cache or throw rateLimited
                if let cached = withState({ cachedQuota }) {
                    return QuotaData(
                        id: cached.id,
                        provider: cached.provider,
                        planName: cached.planName,
                        windows: cached.windows,
                        accountEmail: cached.accountEmail,
                        fetchedAt: cached.fetchedAt,
                        isStale: true
                    )
                }
                throw ProviderError.rateLimited
            }
            // Non-429 errors: return stale cache if available
            if let cached = withState({ cachedQuota }) {
                return QuotaData(
                    id: cached.id,
                    provider: cached.provider,
                    planName: cached.planName,
                    windows: cached.windows,
                    accountEmail: cached.accountEmail,
                    fetchedAt: cached.fetchedAt,
                    isStale: true
                )
            }
            throw error
        } catch {
            // Return cached data as stale if available
            if let cached = withState({ cachedQuota }) {
                return QuotaData(
                    id: cached.id,
                    provider: cached.provider,
                    planName: cached.planName,
                    windows: cached.windows,
                    accountEmail: cached.accountEmail,
                    fetchedAt: cached.fetchedAt,
                    isStale: true
                )
            }
            throw error
        }
    }

    func validate() async throws -> Bool {
        await refreshLocalState()
        return withState { localState.detectionResult.isDetected && localState.accessToken != nil }
    }

    // MARK: - Account Info

    var accountEmail: String? {
        refreshLocalStateSync()
        return withState { localState.accountEmail }
    }

    var subscriptionType: String? {
        refreshLocalStateSync()
        return withState { localState.subscriptionType }
    }

    var planDisplayName: String? {
        guard let sub = subscriptionType else { return nil }
        switch sub.lowercased() {
        case "max": return "Max"
        case "max_5x": return "Max 5x"
        case "pro": return "Pro"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        case "free": return "Free"
        default: return sub.capitalized
        }
    }

    var isLoggedIn: Bool {
        refreshLocalStateSync()
        return withState { localState.accessToken != nil }
    }

    /// Set a manually-provided token (from Settings onboarding)
    func setManualToken(_ token: String) {
        if token.isEmpty {
            withState {
                manualToken = nil
            }
            KeychainService.shared.delete(key: "claude-token")
        } else {
            withState {
                manualToken = token
            }
            try? KeychainService.shared.save(key: "claude-token", value: token)
        }
        refreshLocalStateSync(force: true)
    }

    /// Set a custom config directory path
    func setCustomPath(_ path: String) {
        detector.customConfigPath = path.isEmpty ? nil : path
        refreshLocalStateSync(force: true)
    }

    // MARK: - Auth Chain

    /// Resolve access token using fallback chain:
    /// 1. Manual token (from settings onboarding)
    /// 2. ~/.claude/.credentials.json file
    /// 3. Keychain (silent read)
    private func resolveAccessToken() -> String? {
        // 1. Manual/saved token
        if let manual = withState({ manualToken }), !manual.isEmpty {
            return manual
        }
        if let saved = KeychainService.shared.get(key: "claude-token"), !saved.isEmpty {
            withState {
                manualToken = saved
            }
            return saved
        }

        // 2. Credentials file (~/.claude/.credentials.json)
        if let fileToken = readCredentialsFile() {
            return fileToken
        }

        // 3. Keychain (silent read — uses kSecUseAuthenticationUISkip, NEVER prompts)
        if let keychainToken = ClaudeKeychainReader.accessToken {
            return keychainToken
        }

        return nil
    }

    private func refreshLocalStateSync(force: Bool = false) {
        refreshLock.lock()
        defer { refreshLock.unlock() }

        if force {
            // Ensure manual/periodic refresh sees newly issued credentials immediately.
            ClaudeKeychainReader.clearCache()
        }

        if !force, Date().timeIntervalSince(withState({ localState.updatedAt })) < localStateTTL {
            return
        }

        let detection = detector.detect(forceRefresh: force)
        let globalConfig = readGlobalConfig()
        let credentialsOAuth = readCredentialsFileOAuth()

        let token = resolveAccessToken()
        let email = globalConfig?.oauthAccount?.emailAddress
        let subscription = globalConfig?.oauthAccount?.subscriptionType
            ?? credentialsOAuth?.subscriptionType
            ?? ClaudeKeychainReader.subscriptionType

        withState {
            localState = ClaudeProviderLocalState(
                detectionResult: detection,
                accessToken: token,
                accountEmail: email,
                subscriptionType: subscription,
                updatedAt: Date()
            )
        }
    }

    /// Read OAuth data from ~/.claude/.credentials.json
    private func readCredentialsFileOAuth() -> ClaudeOAuthCredentials.OAuthData? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let credPath = home.appendingPathComponent(".claude/.credentials.json")
        let decoder = JSONDecoder()

        guard let data = try? Data(contentsOf: credPath),
              let creds = try? decoder.decode(ClaudeCredentialsFile.self, from: data),
              let oauth = creds.claudeAiOauth else {
            return nil
        }
        return oauth
    }

    /// Read access token from ~/.claude/.credentials.json
    private func readCredentialsFile() -> String? {
        guard let oauth = readCredentialsFileOAuth(),
              !oauth.isExpired,
              let token = oauth.accessToken else {
            return nil
        }
        return token
    }

    /// Read global config from ~/.claude.json
    private func readGlobalConfig() -> ClaudeGlobalConfig? {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
        let decoder = JSONDecoder()
        guard let data = try? Data(contentsOf: configPath) else { return nil }
        return try? decoder.decode(ClaudeGlobalConfig.self, from: data)
    }

    // MARK: - API

    /// Fetch quota from Claude API (same endpoint as claude-meter)
    private func fetchFromAPI(token: String) async throws -> QuotaData {
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

        let headers = [
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "QDock/1.0",
            "anthropic-beta": "oauth-2025-04-20",
        ]

        let response = try await NetworkClient.shared.get(
            url: url,
            headers: headers,
            responseType: ClaudeUsageResponse.self
        )

        return response.toQuotaData(
            provider: name,
            planName: planDisplayName,
            email: withState { localState.accountEmail }
        )
    }

    // MARK: - Token Refresh

    /// Attempt to refresh the access token. Returns the new token on success, nil on failure.
    /// Serialized via `tokenRefreshLock` to prevent concurrent refresh attempts.
    private func tryRefreshToken() async -> String? {
        // Serialize: only one refresh at a time
        let acquired = claimRefreshSlot()
        guard acquired else { return nil }
        defer { releaseRefreshSlot() }

        guard let refreshToken = resolveRefreshToken() else {
            return nil
        }

        do {
            let tokens = try await tokenRefresher.refresh(using: refreshToken)
            persistRefreshedTokens(tokens)
            return tokens.accessToken
        } catch {
            return nil
        }
    }

    /// Try to claim the refresh slot. Returns true if this caller should proceed.
    private func claimRefreshSlot() -> Bool {
        tokenRefreshLock.lock()
        defer { tokenRefreshLock.unlock() }
        if isRefreshingToken { return false }
        isRefreshingToken = true
        return true
    }

    /// Release the refresh slot after completion.
    private func releaseRefreshSlot() {
        tokenRefreshLock.lock()
        defer { tokenRefreshLock.unlock() }
        isRefreshingToken = false
    }

    /// Find a refresh token from available sources:
    /// 1. QDock Keychain (`claude-refresh-token`)
    /// 2. ~/.claude/.credentials.json
    /// 3. Claude Code Keychain (via security CLI)
    private func resolveRefreshToken() -> String? {
        // 1. QDock's own keychain
        if let saved = KeychainService.shared.get(key: "claude-refresh-token"), !saved.isEmpty {
            return saved
        }

        // 2. Credentials file
        if let oauth = readCredentialsFileOAuth(), let rt = oauth.refreshToken, !rt.isEmpty {
            return rt
        }

        // 3. Claude Code keychain
        if let creds = ClaudeKeychainReader.readCredentials(),
           let rt = creds.claudeAiOauth?.refreshToken, !rt.isEmpty {
            return rt
        }

        return nil
    }

    /// Persist refreshed tokens to all stores so both QDock and Claude Code benefit.
    private func persistRefreshedTokens(_ tokens: ClaudeTokenRefresher.RefreshedTokens) {
        let expiresAtMs = Int64((Date().timeIntervalSince1970 + Double(tokens.expiresIn)) * 1000)

        // 1. Write to ~/.claude/.credentials.json (atomic)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let credPath = home.appendingPathComponent(".claude/.credentials.json")

        // Read existing file to preserve other fields
        var fileDict: [String: Any] = [:]
        if let existingData = try? Data(contentsOf: credPath),
           let existing = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            fileDict = existing
        }

        // Update the oauth section
        var oauthDict: [String: Any] = (fileDict["claude_ai_oauth"] as? [String: Any]) ?? [:]
        oauthDict["access_token"] = tokens.accessToken
        oauthDict["refresh_token"] = tokens.refreshToken
        oauthDict["expires_at"] = expiresAtMs
        fileDict["claude_ai_oauth"] = oauthDict

        if let jsonData = try? JSONSerialization.data(withJSONObject: fileDict, options: [.prettyPrinted, .sortedKeys]) {
            try? jsonData.write(to: credPath, options: .atomic)
        }

        // 2. Save to QDock Keychain
        try? KeychainService.shared.save(key: "claude-token", value: tokens.accessToken)
        try? KeychainService.shared.save(key: "claude-refresh-token", value: tokens.refreshToken)

        // 3. Update in-memory state
        ClaudeKeychainReader.clearCache()
        withState {
            manualToken = tokens.accessToken
        }
        refreshLocalStateSync(force: true)
    }

    private func withState<T>(_ block: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return block()
    }
}

private struct ClaudeProviderLocalState {
    let detectionResult: ClaudeCodeDetector.DetectionResult
    let accessToken: String?
    let accountEmail: String?
    let subscriptionType: String?
    let updatedAt: Date

    static var empty: ClaudeProviderLocalState {
        ClaudeProviderLocalState(
            detectionResult: .notFound,
            accessToken: nil,
            accountEmail: nil,
            subscriptionType: nil,
            updatedAt: .distantPast
        )
    }
}
