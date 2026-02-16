import Foundation
import SwiftUI

/// Manages all usage providers and orchestrates data fetching
@MainActor
final class ProviderManager: ObservableObject {
    @Published var providers: [any UsageProvider] = []
    @Published var usageByProvider: [String: UsageData] = [:]
    @Published var errorsByProvider: [String: String] = [:]
    @Published var loadingProviders: Set<String> = []
    @Published var selectedPeriod: UsagePeriod = .today

    /// Total cost across all providers
    var totalCost: Decimal {
        usageByProvider.values.reduce(0) { $0 + $1.totalCostUSD }
    }

    /// Total tokens across all providers
    var totalTokens: Int {
        usageByProvider.values.reduce(0) { $0 + $1.totalTokens }
    }

    /// Active (enabled + configured) providers
    var activeProviders: [any UsageProvider] {
        providers.filter { $0.isEnabled && $0.isConfigured }
    }

    init() {
        setupDefaultProviders()
    }

    /// The Claude Code local provider (always first if detected)
    var claudeCodeProvider: ClaudeCodeProvider? {
        providers.first { $0.id == "claude-code-local" } as? ClaudeCodeProvider
    }

    private func setupDefaultProviders() {
        var result: [any UsageProvider] = []

        // Auto-detect Claude Code installation — no API key needed
        let claudeCode = ClaudeCodeProvider()
        if claudeCode.isConfigured {
            claudeCode.isEnabled = true
            result.append(claudeCode)
        }

        // API-based providers (require manual key setup)
        result.append(AnthropicProvider())
        result.append(OpenAIProvider())
        result.append(OpenRouterProvider())

        providers = result
    }

    /// Fetch usage from all active providers
    func fetchAll() async {
        await withTaskGroup(of: Void.self) { group in
            for provider in activeProviders {
                group.addTask { [weak self] in
                    await self?.fetchUsage(for: provider)
                }
            }
        }
    }

    /// Fetch usage for a single provider
    func fetchUsage(for provider: any UsageProvider) async {
        let id = provider.id
        loadingProviders.insert(id)
        errorsByProvider.removeValue(forKey: id)

        do {
            let usage = try await provider.fetchUsage(for: selectedPeriod)
            usageByProvider[id] = usage
        } catch {
            errorsByProvider[id] = error.localizedDescription
        }

        loadingProviders.remove(id)
    }

    /// Save API key for a provider
    func setAPIKey(_ key: String, for providerId: String) {
        guard let provider = providers.first(where: { $0.id == providerId }) else { return }

        let keychainKey = "\(providerId)-api-key"
        if key.isEmpty {
            KeychainService.shared.delete(key: keychainKey)
        } else {
            try? KeychainService.shared.save(key: keychainKey, value: key)
        }

        // Trigger UI update
        objectWillChange.send()

        // Auto-enable if key is set
        if !key.isEmpty {
            provider.isEnabled = true
        }
    }

    /// Get API key for a provider
    func getAPIKey(for providerId: String) -> String {
        KeychainService.shared.get(key: "\(providerId)-api-key") ?? ""
    }

    /// Toggle provider enabled state
    func toggleProvider(_ providerId: String) {
        guard let provider = providers.first(where: { $0.id == providerId }) else { return }
        provider.isEnabled.toggle()
        objectWillChange.send()

        if !provider.isEnabled {
            usageByProvider.removeValue(forKey: providerId)
            errorsByProvider.removeValue(forKey: providerId)
        }
    }
}
