import Foundation

/// Claude Code quota provider — fetches usage limits from Claude API
///
/// Auth chain (avoids Keychain prompts):
/// 1. ~/.claude/.credentials.json file
/// 2. Keychain (silent read — no prompt if accessible)
/// 3. In-app onboarding fallback
///
/// Data source:
/// - Primary: GET https://api.anthropic.com/api/oauth/usage
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
        withState { localState.detectionResult.isDetected }
    }

    var authStatus: AuthStatus {
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
            if case .httpError(let statusCode, _, let retryAfterSeconds) = error {
                // 401/403: expired token — refresh and retry
                if statusCode == 401 || statusCode == 403 {
                    // A token without user:profile is rejected by the usage
                    // endpoint no matter how fresh it is — refreshing won't
                    // help, so give actionable guidance instead.
                    if withState({ localState.missingProfileScope }) {
                        throw ProviderError.authRequired(
                            "This token lacks the user:profile scope required for usage data. Run `claude /login` in your terminal to re-authenticate."
                        )
                    }
                    if let newToken = await tryRefreshToken() {
                        do {
                            let quota = try await fetchFromAPI(token: newToken)
                            withState { cachedQuota = quota }
                            return quota
                        } catch {
                            // Retry failed — fall through to stale cache
                        }
                    }
                    return try returnStaleOrThrow(ProviderError.tokenExpired)
                }

                // 429: rate limited — DON'T refresh token
                if statusCode == 429 {
                    if let cached = withState({ cachedQuota }) {
                        return staleQuota(from: cached)
                    }
                    throw ProviderError.rateLimited(retryAfterSeconds: retryAfterSeconds)
                }
            }
            // Other HTTP errors: return stale cache if available
            return try returnStaleOrThrow(error)
        } catch {
            return try returnStaleOrThrow(error)
        }
    }

    func validate() async throws -> Bool {
        await refreshLocalState()
        return withState { localState.detectionResult.isDetected && localState.accessToken != nil }
    }

    // MARK: - Account Info

    var accountEmail: String? {
        withState { localState.accountEmail }
    }

    var subscriptionType: String? {
        withState { localState.subscriptionType }
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
        withState { localState.accessToken != nil }
    }

    /// true when the active token is known to lack the `user:profile`
    /// scope required by the usage endpoint (e.g. `claude setup-token`).
    var missingProfileScope: Bool {
        withState { localState.missingProfileScope }
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

    private struct ResolvedToken {
        let token: String
        /// Scopes granted to this token, when the source records them.
        /// nil = unknown (e.g. manually pasted tokens).
        let scopes: [String]?
    }

    /// Resolve access token using fallback chain:
    /// 1. ~/.claude/.credentials.json file (most up-to-date, CLI writes here on refresh)
    /// 2. Keychain (silent read, has expiry check)
    /// 3. Manual token (from settings onboarding, fallback)
    private func resolveAccessTokenWithScopes() -> ResolvedToken? {
        // 1. Credentials file — CLI always writes the freshest token here
        if let oauth = readCredentialsFileOAuth(),
           !oauth.isExpired,
           let fileToken = oauth.accessToken {
            return ResolvedToken(token: fileToken, scopes: oauth.scopes)
        }

        // 2. Keychain (silent read — uses kSecUseAuthenticationUISkip, NEVER prompts)
        if let keychainToken = ClaudeKeychainReader.accessToken {
            return ResolvedToken(token: keychainToken, scopes: ClaudeKeychainReader.tokenScopes)
        }

        // 3. Manual/saved token (fallback from settings onboarding)
        if let manual = withState({ manualToken }), !manual.isEmpty {
            return ResolvedToken(token: manual, scopes: nil)
        }
        if let saved = KeychainService.shared.get(key: "claude-token"), !saved.isEmpty {
            withState {
                manualToken = saved
            }
            return ResolvedToken(token: saved, scopes: nil)
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

        let resolved = resolveAccessTokenWithScopes()
        let email = globalConfig?.oauthAccount?.emailAddress
        let subscription = globalConfig?.oauthAccount?.subscriptionType
            ?? credentialsOAuth?.subscriptionType
            ?? ClaudeKeychainReader.subscriptionType

        withState {
            localState = ClaudeProviderLocalState(
                detectionResult: detection,
                accessToken: resolved?.token,
                tokenScopes: resolved?.scopes,
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
    /// Read global config from ~/.claude.json
    private func readGlobalConfig() -> ClaudeGlobalConfig? {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
        let decoder = JSONDecoder()
        guard let data = try? Data(contentsOf: configPath) else { return nil }
        return try? decoder.decode(ClaudeGlobalConfig.self, from: data)
    }

    // MARK: - Stale Cache Helpers

    private func staleQuota(from cached: QuotaData) -> QuotaData {
        QuotaData(
            id: cached.id,
            provider: cached.provider,
            planName: cached.planName,
            windows: cached.windows,
            accountEmail: cached.accountEmail,
            fetchedAt: cached.fetchedAt,
            isStale: true
        )
    }

    private func returnStaleOrThrow(_ error: Error) throws -> QuotaData {
        if let cached = withState({ cachedQuota }) {
            return staleQuota(from: cached)
        }
        throw error
    }

    // MARK: - API

    /// Version claimed when the local CLI can't be asked. Only the product
    /// prefix appears to select the bucket, but send a plausible semver.
    private static let fallbackCLIVersion = "2.0.0"

    /// The oauth/usage endpoint buckets rate limits by User-Agent: anything
    /// other than "claude-code/<version>" lands in an aggressively limited
    /// bucket where even 5-minute polling draws escalating 429 penalties
    /// (see anthropics/claude-code#31637, #30930).
    private func apiUserAgent() -> String {
        "claude-code/\(detector.cliVersion() ?? Self.fallbackCLIVersion)"
    }

    /// Fetch quota from Claude API (same endpoint as claude-meter)
    private func fetchFromAPI(token: String) async throws -> QuotaData {
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

        AppLog.refresh.info("usage fetch, UA \(self.apiUserAgent(), privacy: .public)")
        let headers = [
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": apiUserAgent(),
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
            let tokens = try await tokenRefresher.refresh(using: refreshToken, userAgent: apiUserAgent())
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
    let tokenScopes: [String]?
    let accountEmail: String?
    let subscriptionType: String?
    let updatedAt: Date

    /// true when the token's scopes are known and lack `user:profile`,
    /// which the usage endpoint requires (setup-token yields such tokens).
    var missingProfileScope: Bool {
        guard let tokenScopes, accessToken != nil else { return false }
        return !tokenScopes.contains("user:profile")
    }

    static var empty: ClaudeProviderLocalState {
        ClaudeProviderLocalState(
            detectionResult: .notFound,
            accessToken: nil,
            tokenScopes: nil,
            accountEmail: nil,
            subscriptionType: nil,
            updatedAt: .distantPast
        )
    }
}
