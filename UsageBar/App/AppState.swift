import Foundation
import SwiftUI
import Observation

enum MenuBarUsageSource: String, CaseIterable, Identifiable {
    case highestUsage = "highest-usage"
    case selectedProvider = "selected-provider"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .highestUsage:
            return "Highest Usage"
        case .selectedProvider:
            return "Specific Provider"
        }
    }
}

struct MenuBarPresentation: Equatable {
    let percent: Double
    let roundedPercent: Int
    let text: String?
    let level: UsageLevel
}

/// Central application state managing providers, refresh, and navigation
@Observable
@MainActor
final class AppState {
    let providerManager: ProviderManager
    let refreshService: RefreshService
    let sessionWatcher: SessionFileWatcher

    var selectedProvider: (any QuotaProvider)?
    var showingSettings = false

    // User preferences
    var refreshIntervalSeconds: Double {
        didSet {
            guard hasFinishedInitialization, refreshIntervalSeconds != oldValue else { return }
            userDefaults.set(refreshIntervalSeconds, forKey: Keys.refreshIntervalSeconds)
            refreshService.updateInterval(refreshIntervalSeconds)
        }
    }
    var showPercentInMenuBar: Bool {
        didSet {
            guard hasFinishedInitialization, showPercentInMenuBar != oldValue else { return }
            userDefaults.set(showPercentInMenuBar, forKey: Keys.showPercentInMenuBar)
            emitMenuBarPresentationIfNeeded()
        }
    }
    var menuBarUsageSourceRaw: String {
        didSet {
            guard hasFinishedInitialization, menuBarUsageSourceRaw != oldValue else { return }
            userDefaults.set(menuBarUsageSourceRaw, forKey: Keys.menuBarUsageSource)
            ensureMenuBarProviderSelection()
            emitMenuBarPresentationIfNeeded()
        }
    }
    var menuBarProviderId: String {
        didSet {
            guard hasFinishedInitialization, menuBarProviderId != oldValue else { return }
            userDefaults.set(menuBarProviderId, forKey: Keys.menuBarProviderId)
            emitMenuBarPresentationIfNeeded()
        }
    }
    var launchAtLogin: Bool {
        didSet {
            guard hasFinishedInitialization, launchAtLogin != oldValue else { return }
            userDefaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }

    @ObservationIgnored
    var onMenuBarPresentationChanged: ((MenuBarPresentation) -> Void)?

    @ObservationIgnored
    private let userDefaults: UserDefaults
    @ObservationIgnored
    private var hasFinishedInitialization = false
    @ObservationIgnored
    private var lastDynamicRefreshInterval: TimeInterval?
    @ObservationIgnored
    private var lastMenuBarPresentation: MenuBarPresentation?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.providerManager = ProviderManager()
        self.refreshService = RefreshService()
        self.sessionWatcher = SessionFileWatcher()

        self.refreshIntervalSeconds = userDefaults.object(forKey: Keys.refreshIntervalSeconds) as? Double ?? 120
        self.showPercentInMenuBar = userDefaults.object(forKey: Keys.showPercentInMenuBar) as? Bool ?? true
        self.menuBarUsageSourceRaw = userDefaults.string(forKey: Keys.menuBarUsageSource) ?? MenuBarUsageSource.highestUsage.rawValue
        self.menuBarProviderId = userDefaults.string(forKey: Keys.menuBarProviderId) ?? ""
        self.launchAtLogin = userDefaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false

        providerManager.onStateChanged = { [weak self] in
            guard let self else { return }
            self.ensureMenuBarProviderSelection()
            self.updateDynamicRefreshInterval()
            self.emitMenuBarPresentationIfNeeded()
        }

        refreshService.configure { [weak self] in
            guard let self else { return }
            await self.providerManager.fetchAll()
            self.ensureMenuBarProviderSelection()
            self.updateDynamicRefreshInterval()
            self.emitMenuBarPresentationIfNeeded()
        }

        refreshService.updateInterval(refreshIntervalSeconds)

        // Watch for Claude Code session file changes
        sessionWatcher.configure { [weak self] in
            guard let self else { return }
            if let ccProvider = self.providerManager.claudeCodeProvider {
                await self.providerManager.fetchQuota(for: ccProvider)
                self.ensureMenuBarProviderSelection()
                self.updateDynamicRefreshInterval()
                self.emitMenuBarPresentationIfNeeded()
            }
        }
        sessionWatcher.startWatching()

        ensureMenuBarProviderSelection()
        hasFinishedInitialization = true
        emitMenuBarPresentationIfNeeded()
    }

    /// Initial data load
    func initialLoad() async {
        await refreshService.refresh()
        ensureMenuBarProviderSelection()
        updateDynamicRefreshInterval()
        emitMenuBarPresentationIfNeeded()
    }

    /// Manual refresh triggered by user
    func manualRefresh() async {
        await refreshService.refresh()
        ensureMenuBarProviderSelection()
        updateDynamicRefreshInterval()
        emitMenuBarPresentationIfNeeded()
    }

    func toggleProvider(_ providerId: String) {
        providerManager.toggleProvider(providerId)
        ensureMenuBarProviderSelection()
        updateDynamicRefreshInterval()
        emitMenuBarPresentationIfNeeded()
    }

    // MARK: - Menu Bar

    var menuBarUsageSource: MenuBarUsageSource {
        get { MenuBarUsageSource(rawValue: menuBarUsageSourceRaw) ?? .highestUsage }
        set { menuBarUsageSourceRaw = newValue.rawValue }
    }

    private var selectedMenuBarProvider: (any QuotaProvider)? {
        let activeProviders = providerManager.activeProviders
        guard !activeProviders.isEmpty else { return nil }

        if let provider = activeProviders.first(where: { $0.id == menuBarProviderId }) {
            return provider
        }

        return activeProviders.first
    }

    var menuBarPercent: Double {
        switch menuBarUsageSource {
        case .highestUsage:
            return providerManager.maxUsagePercent
        case .selectedProvider:
            guard let provider = selectedMenuBarProvider,
                  let quota = providerManager.quotaByProvider[provider.id] else {
                return 0
            }
            return quota.maxUsagePercent
        }
    }

    /// Menu bar display text — shows highest usage percent
    var menuBarText: String? {
        guard showPercentInMenuBar else { return nil }

        switch menuBarUsageSource {
        case .highestUsage:
            let percent = menuBarPercent
            if percent > 0 {
                return "\(Int(percent))%"
            }
            return nil
        case .selectedProvider:
            guard let provider = selectedMenuBarProvider,
                  providerManager.quotaByProvider[provider.id] != nil else {
                return nil
            }
            return "\(Int(menuBarPercent))%"
        }
    }

    /// Menu bar usage level for coloring
    var menuBarLevel: UsageLevel {
        UsageLevel.from(percent: menuBarPercent)
    }

    var menuBarPresentation: MenuBarPresentation {
        let percent = menuBarPercent
        return MenuBarPresentation(
            percent: percent,
            roundedPercent: Int(percent.rounded(.down)),
            text: menuBarText,
            level: UsageLevel.from(percent: percent)
        )
    }

    var availableMenuBarProviders: [any QuotaProvider] {
        providerManager.activeProviders
    }

    func ensureMenuBarProviderSelection() {
        guard !providerManager.activeProviders.isEmpty else {
            menuBarProviderId = ""
            return
        }

        if providerManager.activeProviders.contains(where: { $0.id == menuBarProviderId }) {
            return
        }

        menuBarProviderId = providerManager.activeProviders.first?.id ?? ""
    }

    // MARK: - Dynamic Refresh

    /// Update refresh interval based on usage level
    func updateDynamicRefreshInterval() {
        let percent = providerManager.maxUsagePercent
        let interval: TimeInterval
        if percent >= 75 {
            interval = 60   // High usage: every minute
        } else if percent > 0 {
            interval = 120  // Normal: every 2 minutes
        } else {
            interval = 300  // Idle: every 5 minutes
        }
        guard interval != lastDynamicRefreshInterval else { return }
        lastDynamicRefreshInterval = interval
        refreshService.updateInterval(interval)
    }

    func emitMenuBarPresentationIfNeeded() {
        let presentation = menuBarPresentation
        guard presentation != lastMenuBarPresentation else { return }
        lastMenuBarPresentation = presentation
        onMenuBarPresentationChanged?(presentation)
    }

}

private extension AppState {
    enum Keys {
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let showPercentInMenuBar = "showPercentInMenuBar"
        static let menuBarUsageSource = "menuBarUsageSource"
        static let menuBarProviderId = "menuBarProviderId"
        static let launchAtLogin = "launchAtLogin"
    }
}
