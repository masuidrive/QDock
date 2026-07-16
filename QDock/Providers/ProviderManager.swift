import Foundation
import Observation

/// Manages all quota providers and orchestrates data fetching
@Observable
@MainActor
final class ProviderManager {
    var providers: [any QuotaProvider] = []
    var quotaByProvider: [String: QuotaData] = [:] {
        didSet {
            guard quotaByProvider != oldValue else { return }
            persistQuotaCache()
        }
    }
    var errorsByProvider: [String: String] = [:]
    var loadingProviders: Set<String> = []
    @ObservationIgnored
    var onStateChanged: (() -> Void)?

    private var providersRevision: UInt64 = 0
    @ObservationIgnored
    private var fetchingProviders: Set<String> = []
    // Observable (not ignored) so the dashboard can surface active cooldowns
    private var rateLimitedUntil: [String: Date] = [:] {
        didSet { persistRateLimitCooldowns() }
    }

    /// End of the latest active rate limit cooldown across providers, if any.
    /// The dashboard shows this instead of pretending the schedule is normal.
    func activeRateLimitCooldownEnd(asOf now: Date = Date()) -> Date? {
        rateLimitedUntil.values.filter { $0 > now }.max()
    }
    @ObservationIgnored
    private var rateLimitRetryTasks: [String: Task<Void, Never>] = [:]

    /// Cooldown applied on a 429 without a Retry-After header.
    private static let defaultRateLimitCooldown: TimeInterval = 300
    private static let rateLimitedUntilKey = "rateLimitedUntilByProvider"

    /// Floor between two real fetches for the same provider, regardless of
    /// trigger. Keeps the manual refresh button from producing bursts.
    private static let minimumFetchSpacing: TimeInterval = 60
    @ObservationIgnored
    private var lastFetchStartedAt: [String: Date] = [:]

    private static let cachedQuotaKey = "cachedQuotaByProvider"

    /// Maximum usage percent across all providers
    var maxUsagePercent: Double {
        quotaByProvider.values.map(\.maxUsagePercent).max() ?? 0
    }

    /// Maximum session usage percent across all providers (for menu bar behavior)
    var maxSessionUsagePercent: Double {
        quotaByProvider.values.map(\.sessionUsagePercent).max() ?? 0
    }

    /// Overall usage level across all windows
    var overallLevel: UsageLevel {
        UsageLevel.from(percent: maxUsagePercent)
    }

    /// Active (enabled + configured) providers
    var activeProviders: [any QuotaProvider] {
        _ = providersRevision
        return providers.filter { $0.isEnabled && $0.isConfigured }
    }

    /// Earliest reset time across all providers
    var earliestReset: Date? {
        quotaByProvider.values.compactMap(\.earliestReset).min()
    }

    /// Formatted countdown for the earliest reset
    var earliestResetCountdown: String? {
        guard let resetDate = earliestReset else { return nil }
        let remaining = resetDate.timeIntervalSinceNow
        guard remaining > 0 else { return nil }

        let totalMinutes = Int(remaining) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else {
            return "Resets in \(minutes)m"
        }
    }

    /// Most recent moment any provider's data actually arrived. Used to
    /// gate the launch fetch: with fresh cached data there is nothing to ask.
    var latestFetchedAt: Date? {
        quotaByProvider.values.map(\.fetchedAt).max()
    }

    init() {
        loadPersistedRateLimitCooldowns()
        loadPersistedQuotaCache()
        setupProviders()
    }

    private func setupProviders() {
        var result: [any QuotaProvider] = []

        // Claude Code — auto-detect
        let claudeCode = ClaudeCodeProvider()
        if claudeCode.isConfigured {
            claudeCode.isEnabled = true
        }
        result.append(claudeCode)

        // Codex CLI — auto-detect
        let codex = CodexProvider()
        if codex.isConfigured {
            codex.isEnabled = true
        }
        result.append(codex)

        providers = result
    }

    func refreshProviderLocalStates() async {
        for provider in providers {
            await provider.refreshLocalState()
        }
        pruneInactiveProviderState()
        providersRevision &+= 1
        notifyStateChanged()
    }

    func refreshProviderLocalState(for providerId: String) async {
        guard let provider = providers.first(where: { $0.id == providerId }) else { return }
        await provider.refreshLocalState()
        pruneInactiveProviderState()
        providersRevision &+= 1
        notifyStateChanged()
    }

    /// Fetch quota from all active providers
    func fetchAll() async {
        await refreshProviderLocalStates()
        let providersToFetch = activeProviders

        await withTaskGroup(of: Void.self) { group in
            for provider in providersToFetch {
                group.addTask { [weak self] in
                    await self?.fetchQuota(for: provider)
                }
            }
        }
    }

    /// Fetch quota for a single provider with timeout.
    /// Prevents duplicate concurrent fetches for the same provider.
    func fetchQuota(for provider: any QuotaProvider) async {
        let id = provider.id

        // Prevent duplicate concurrent fetches
        guard !fetchingProviders.contains(id) else { return }

        // Honor the API's Retry-After: while cooling down, no request may
        // go out from ANY trigger (timer, popover, watcher, buttons) -
        // polling during the penalty window keeps extending it.
        if let cooldownEnd = rateLimitedUntil[id], Date() < cooldownEnd {
            AppLog.refresh.info("fetch \(id, privacy: .public) skipped: rate limit cooldown, \(Int(cooldownEnd.timeIntervalSinceNow))s left")
            // After a relaunch into a persisted cooldown there is no error
            // set yet; surface the wait instead of an empty provider row.
            if quotaByProvider[id] == nil, errorsByProvider[id] == nil {
                setErrorIfNeeded(
                    ProviderError.rateLimited(retryAfterSeconds: cooldownEnd.timeIntervalSinceNow).localizedDescription,
                    for: id
                )
                notifyStateChanged()
            }
            return
        }

        if let lastStart = lastFetchStartedAt[id],
           Date().timeIntervalSince(lastStart) < Self.minimumFetchSpacing {
            AppLog.refresh.info("fetch \(id, privacy: .public) skipped: within \(Int(Self.minimumFetchSpacing))s spacing floor")
            return
        }

        fetchingProviders.insert(id)
        defer { fetchingProviders.remove(id) }
        lastFetchStartedAt[id] = Date()

        // No pre-fetch refreshLocalState() here: providers refresh it inside
        // fetchQuota(), which runs under the 15s timeout race below. Anything
        // awaited outside that race can wedge the refresh pipeline for good.

        if !loadingProviders.contains(id) {
            loadingProviders.insert(id)
        }
        if errorsByProvider[id] != nil {
            errorsByProvider.removeValue(forKey: id)
        }

        do {
            let quota = try await withThrowingTaskGroup(of: QuotaData.self) { group in
                group.addTask {
                    try await provider.fetchQuota()
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(15))
                    throw ProviderError.apiError("Request timed out after 15s")
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            if shouldStoreQuota(quota, for: id) {
                quotaByProvider[id] = quota
            }
            // Clear any rate limit cooldown on success
            rateLimitedUntil.removeValue(forKey: id)
        } catch is CancellationError {
            setErrorIfNeeded("Request cancelled", for: id)
        } catch {
            // On rate limiting: don't show error if we have data, go silent
            // until the API's Retry-After expires, then retry once
            if let retryAfter = rateLimitRetryAfter(from: error) {
                if quotaByProvider[id] != nil {
                    errorsByProvider.removeValue(forKey: id)
                } else {
                    setErrorIfNeeded(error.localizedDescription, for: id)
                }
                beginRateLimitCooldown(for: provider, retryAfterSeconds: retryAfter)
            } else {
                setErrorIfNeeded(error.localizedDescription, for: id)
                if shouldClearQuota(for: error) {
                    quotaByProvider.removeValue(forKey: id)
                }
            }
        }

        loadingProviders.remove(id)
        notifyStateChanged()
    }

    /// Toggle provider enabled state
    func toggleProvider(_ providerId: String) {
        guard let index = providers.firstIndex(where: { $0.id == providerId }) else { return }
        providers[index].isEnabled.toggle()
        providersRevision &+= 1

        let provider = providers[index]

        if provider.isEnabled {
            // Fetch data immediately when enabled
            Task { [weak self] in
                await self?.fetchQuota(for: provider)
            }
        } else {
            quotaByProvider.removeValue(forKey: providerId)
            errorsByProvider.removeValue(forKey: providerId)
        }
        notifyStateChanged()
    }

    private func setErrorIfNeeded(_ message: String, for providerId: String) {
        guard errorsByProvider[providerId] != message else { return }
        errorsByProvider[providerId] = message
    }

    private func shouldClearQuota(for error: Error) -> Bool {
        guard let providerError = error as? ProviderError else { return false }
        switch providerError {
        case .notConfigured, .notInstalled, .authRequired, .tokenExpired:
            return true
        case .rateLimited, .networkError, .apiError, .parseError:
            return false
        }
    }

    private func pruneInactiveProviderState() {
        let activeProviderIDs = Set(
            providers
                .filter { $0.isEnabled && $0.isConfigured }
                .map(\.id)
        )

        quotaByProvider = quotaByProvider.filter { activeProviderIDs.contains($0.key) }
        errorsByProvider = errorsByProvider.filter { activeProviderIDs.contains($0.key) }
    }

    private func shouldStoreQuota(_ newQuota: QuotaData, for providerId: String) -> Bool {
        guard let existing = quotaByProvider[providerId] else { return true }
        return existing.windows != newQuota.windows
            || existing.planName != newQuota.planName
            || existing.accountEmail != newQuota.accountEmail
            || existing.isStale != newQuota.isStale
            || existing.fetchedAt != newQuota.fetchedAt
    }

    /// The effective cooldown for a rate limit error, or nil if the error
    /// is not a rate limit.
    private func rateLimitRetryAfter(from error: Error) -> TimeInterval? {
        guard let providerError = error as? ProviderError,
              case .rateLimited(let retryAfterSeconds) = providerError else {
            return nil
        }
        guard let seconds = retryAfterSeconds, seconds > 0 else {
            return Self.defaultRateLimitCooldown
        }
        return seconds
    }

    /// Cooldowns survive relaunches: rate limit penalties escalate when
    /// polled, and testing/updating the app must not restart the clock
    /// with a doomed launch-time request.
    private func loadPersistedRateLimitCooldowns() {
        let stored = UserDefaults.standard.dictionary(forKey: Self.rateLimitedUntilKey) as? [String: Double] ?? [:]
        let now = Date()
        rateLimitedUntil = stored
            .mapValues { Date(timeIntervalSince1970: $0) }
            .filter { $0.value > now }
    }

    /// The quota cache survives relaunches so the UI has data instantly
    /// and a launch doesn't need an API request while the data is fresh.
    private func loadPersistedQuotaCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.cachedQuotaKey),
              let cached = try? JSONDecoder().decode([String: QuotaData].self, from: data) else {
            return
        }
        quotaByProvider = cached
    }

    private func persistQuotaCache() {
        guard let data = try? JSONEncoder().encode(quotaByProvider) else { return }
        UserDefaults.standard.set(data, forKey: Self.cachedQuotaKey)
    }

    private func persistRateLimitCooldowns() {
        if rateLimitedUntil.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.rateLimitedUntilKey)
        } else {
            UserDefaults.standard.set(
                rateLimitedUntil.mapValues { $0.timeIntervalSince1970 },
                forKey: Self.rateLimitedUntilKey
            )
        }
    }

    /// Block all requests for this provider until the cooldown expires,
    /// then retry once (the regular timer takes over from there).
    private func beginRateLimitCooldown(for provider: any QuotaProvider, retryAfterSeconds: TimeInterval) {
        let id = provider.id
        rateLimitedUntil[id] = Date().addingTimeInterval(retryAfterSeconds)
        AppLog.refresh.warning("rate limited: \(id, privacy: .public) cooling down for \(Int(retryAfterSeconds))s")

        rateLimitRetryTasks[id]?.cancel()
        rateLimitRetryTasks[id] = Task { [weak self] in
            // Small buffer past the window so the retry lands cleanly after it
            try? await Task.sleep(for: .seconds(retryAfterSeconds + 5))
            guard !Task.isCancelled, let self else { return }
            self.rateLimitedUntil.removeValue(forKey: id)
            await self.fetchQuota(for: provider)
        }
    }

    private func notifyStateChanged() {
        onStateChanged?()
    }
}
