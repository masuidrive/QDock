import Foundation

/// OpenAI Codex CLI quota provider
/// Uses `codex app-server` JSON-RPC to fetch rate limit data
///
/// Detection: ~/.codex/ directory or codex binary in PATH
/// Data: JSON-RPC via stdio to `codex app-server`
final class CodexProvider: QuotaProvider {
    let id = "codex"
    let name = "Codex CLI"
    let iconName = "apple.terminal"
    let brandColorHex = "#10A37F"
    var isEnabled: Bool = false

    private let codexDir: URL
    private let appServer = CodexAppServer()
    private var cachedQuota: QuotaData?
    private var localState = CodexLocalState.empty
    private let localStateTTL: TimeInterval = 30
    private let stateLock = NSLock()
    private let refreshLock = NSLock()

    init() {
        codexDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
        refreshLocalStateSync(force: true)
    }

    // MARK: - QuotaProvider

    var isConfigured: Bool {
        refreshLocalStateSync()
        return isInstalled
    }

    var authStatus: AuthStatus {
        refreshLocalStateSync()
        guard isInstalled else {
            return .notInstalled(message: "Codex CLI not detected. Install via npm: npm i -g @openai/codex")
        }
        // Codex uses its own auth — no extra setup needed
        return .authenticated(email: nil)
    }

    func refreshLocalState() async {
        refreshLocalStateSync(force: true)
    }

    func fetchQuota() async throws -> QuotaData {
        await refreshLocalState()

        guard isInstalled else {
            throw ProviderError.notInstalled
        }

        do {
            let rateLimits = try await appServer.fetchRateLimits()
            let quota = buildQuotaData(from: rateLimits)
            withState {
                cachedQuota = quota
            }
            return quota
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
        return isInstalled
    }

    // MARK: - Detection

    var isInstalled: Bool {
        withState { localState.isInstalled }
    }

    /// Read Codex config
    var config: CodexConfig? {
        CodexConfig.read()
    }

    var planDisplayName: String? {
        // Codex doesn't expose plan info easily; return nil
        nil
    }

    // MARK: - Helpers

    private func buildQuotaData(from rateLimits: RateLimitsResult) -> QuotaData {
        var windows: [QuotaWindow] = []

        if let primary = rateLimits.primary {
            let resetDate: Date? = {
                guard let ts = primary.resetsAt else { return nil }
                return Date(timeIntervalSince1970: TimeInterval(ts))
            }()

            windows.append(QuotaWindow(
                id: "session",
                displayName: "Session",
                usagePercent: primary.usedPercent ?? 0,
                resetsAt: resetDate,
                windowDurationMinutes: primary.windowDurationMins
            ))
        }

        if let secondary = rateLimits.secondary {
            let resetDate: Date? = {
                guard let ts = secondary.resetsAt else { return nil }
                return Date(timeIntervalSince1970: TimeInterval(ts))
            }()

            windows.append(QuotaWindow(
                id: "weekly",
                displayName: "Weekly",
                usagePercent: secondary.usedPercent ?? 0,
                resetsAt: resetDate,
                windowDurationMinutes: secondary.windowDurationMins
            ))
        }

        let resolvedPlanName = rateLimits.planType.map { formatPlanName($0) } ?? planDisplayName

        return QuotaData(
            id: "codex",
            provider: name,
            planName: resolvedPlanName,
            windows: windows,
            accountEmail: nil,
            fetchedAt: Date(),
            isStale: false
        )
    }

    private func formatPlanName(_ rawPlanType: String) -> String {
        switch rawPlanType.lowercased() {
        case "free": return "Free"
        case "go": return "Go"
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "edu": return "Edu"
        default:
            return rawPlanType.capitalized
        }
    }

    private func refreshLocalStateSync(force: Bool = false) {
        refreshLock.lock()
        defer { refreshLock.unlock() }

        if !force, Date().timeIntervalSince(withState({ localState.updatedAt })) < localStateTTL {
            return
        }

        let hasCodexDir = FileManager.default.fileExists(atPath: codexDir.path)
        let binaryPath = appServer.findCodexBinaryPublic()
        withState {
            localState = CodexLocalState(
                hasCodexDirectory: hasCodexDir,
                binaryPath: binaryPath,
                updatedAt: Date()
            )
        }
    }

    private func withState<T>(_ block: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return block()
    }
}

private struct CodexLocalState {
    let hasCodexDirectory: Bool
    let binaryPath: String?
    let updatedAt: Date

    var isInstalled: Bool {
        hasCodexDirectory && binaryPath != nil
    }

    static var empty: CodexLocalState {
        CodexLocalState(
            hasCodexDirectory: false,
            binaryPath: nil,
            updatedAt: .distantPast
        )
    }
}
