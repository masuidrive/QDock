import Foundation
import Observation

/// Manages all quota providers and orchestrates data fetching
@Observable
@MainActor
final class ProviderManager {
    var providers: [any QuotaProvider] = []
    var quotaByProvider: [String: QuotaData] = [:]
    var errorsByProvider: [String: String] = [:]
    var loadingProviders: Set<String> = []
    @ObservationIgnored
    var onStateChanged: (() -> Void)?

    private var providersRevision: UInt64 = 0

    /// Maximum usage percent across all providers
    var maxUsagePercent: Double {
        quotaByProvider.values.map(\.maxUsagePercent).max() ?? 0
    }

    /// Overall usage level for menu bar coloring
    var overallLevel: UsageLevel {
        UsageLevel.from(percent: maxUsagePercent)
    }

    /// Active (enabled + configured) providers
    var activeProviders: [any QuotaProvider] {
        _ = providersRevision
        return providers.filter { $0.isEnabled && $0.isConfigured }
    }

    /// The Claude Code provider
    var claudeCodeProvider: ClaudeCodeProvider? {
        providers.first { $0.id == "claude-code" } as? ClaudeCodeProvider
    }

    /// The Codex provider
    var codexProvider: CodexProvider? {
        providers.first { $0.id == "codex" } as? CodexProvider
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

    init() {
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
        providersRevision &+= 1
        notifyStateChanged()
    }

    func refreshProviderLocalState(for providerId: String) async {
        guard let provider = providers.first(where: { $0.id == providerId }) else { return }
        await provider.refreshLocalState()
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

    /// Fetch quota for a single provider with timeout
    func fetchQuota(for provider: any QuotaProvider) async {
        let id = provider.id
        await provider.refreshLocalState()

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
        } catch is CancellationError {
            setErrorIfNeeded("Request cancelled", for: id)
        } catch {
            setErrorIfNeeded(error.localizedDescription, for: id)
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

    private func shouldStoreQuota(_ newQuota: QuotaData, for providerId: String) -> Bool {
        guard let existing = quotaByProvider[providerId] else { return true }
        return existing.windows != newQuota.windows
            || existing.planName != newQuota.planName
            || existing.accountEmail != newQuota.accountEmail
            || existing.isStale != newQuota.isStale
    }

    private func notifyStateChanged() {
        onStateChanged?()
    }
}
