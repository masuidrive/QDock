import Foundation
import SwiftUI
import Observation
import UserNotifications

enum MenuBarProvider: String, CaseIterable {
    case claude = "claude-code"
    case codex

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}

struct MenuBarUsage: Equatable, Hashable {
    let provider: MenuBarProvider
    let percent: Double
    let timeProgressPercent: Double?

    var roundedPercent: Int {
        Int(percent.rounded(.down))
    }

    var roundedTimeProgressPercent: Int? {
        timeProgressPercent.map { Int($0.rounded(.down)) }
    }
}

struct MenuBarPresentation: Equatable {
    let usages: [MenuBarUsage]
    let showsPercentText: Bool

    static func make(
        quotaByProvider: [String: QuotaData],
        showsPercentText: Bool,
        at date: Date = Date()
    ) -> MenuBarPresentation {
        let usages = MenuBarProvider.allCases.compactMap { provider -> MenuBarUsage? in
            guard let quota = quotaByProvider[provider.rawValue] else { return nil }
            let window: QuotaWindow?
            switch provider {
            case .claude:
                window = quota.weeklyWindow ?? quota.sessionWindow
            case .codex:
                window = quota.sessionWindow
            }
            let percent = window?.usagePercent ?? 0
            let clamped = percent.isFinite ? max(0, min(percent, 100)) : 0
            let timeProgress = window?.timeProgressPercent(at: date)
            let clampedTimeProgress = timeProgress.flatMap { progress in
                progress.isFinite ? max(0, min(progress, 100)) : nil
            }
            return MenuBarUsage(
                provider: provider,
                percent: clamped,
                timeProgressPercent: clampedTimeProgress
            )
        }
        return MenuBarPresentation(usages: usages, showsPercentText: showsPercentText)
    }
}

/// Central application state managing providers, refresh, and navigation
@Observable
@MainActor
final class AppState {
    let providerManager: ProviderManager
    let refreshService: RefreshService
    let sessionWatcher: SessionFileWatcher
    let appUpdateService: AppUpdateService

    var showingSettings = false
    var availableUpdateVersion: String?
    var availableUpdateURL: URL?
    var isCheckingForUpdates = false
    var lastUpdateCheckError: String?
    var isInstallingUpdate = false
    var updateInstallError: String?
    var installedUpdateVersion: String?

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
    var launchAtLogin: Bool {
        didSet {
            guard hasFinishedInitialization, launchAtLogin != oldValue else { return }
            userDefaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }
    var usageAlertsEnabled: Bool {
        didSet {
            guard hasFinishedInitialization, usageAlertsEnabled != oldValue else { return }
            userDefaults.set(usageAlertsEnabled, forKey: Keys.usageAlertsEnabled)
            usageNotificationService.isEnabled = usageAlertsEnabled
        }
    }
    var appearanceModeRaw: String {
        didSet {
            guard hasFinishedInitialization, appearanceModeRaw != oldValue else { return }
            userDefaults.set(appearanceModeRaw, forKey: Keys.appearanceMode)
            onAppearanceModeChanged?(appearanceMode)
        }
    }

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRaw) ?? .system }
        set { appearanceModeRaw = newValue.rawValue }
    }

    @ObservationIgnored
    var onAppearanceModeChanged: ((AppearanceMode) -> Void)?

    @ObservationIgnored
    let usageNotificationService = UsageNotificationService()

    @ObservationIgnored
    var onMenuBarPresentationChanged: ((MenuBarPresentation) -> Void)?

    @ObservationIgnored
    private let userDefaults: UserDefaults
    @ObservationIgnored
    private var hasFinishedInitialization = false
    @ObservationIgnored
    private var lastMenuBarPresentation: MenuBarPresentation?
    @ObservationIgnored
    private var lastUpdateCheckDate: Date?
    @ObservationIgnored
    private var availableRelease: AppReleaseInfo?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.providerManager = ProviderManager()
        self.refreshService = RefreshService()
        self.sessionWatcher = SessionFileWatcher()
        self.appUpdateService = AppUpdateService()

        // Snap legacy stored choices (removed 1/2/4-minute options) onto a
        // currently offered interval; 0 stays as "Manual only".
        let storedInterval = userDefaults.object(forKey: Keys.refreshIntervalSeconds) as? Double
        self.refreshIntervalSeconds = storedInterval.map(RefreshInterval.normalized(fromStored:))
            ?? RefreshInterval.default.rawValue
        self.showPercentInMenuBar = userDefaults.object(forKey: Keys.showPercentInMenuBar) as? Bool ?? true
        self.launchAtLogin = userDefaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        self.usageAlertsEnabled = userDefaults.object(forKey: Keys.usageAlertsEnabled) as? Bool ?? true
        self.appearanceModeRaw = userDefaults.string(forKey: Keys.appearanceMode) ?? AppearanceMode.system.rawValue
        usageNotificationService.isEnabled = usageAlertsEnabled

        providerManager.onStateChanged = { [weak self] in
            guard let self else { return }
            self.emitMenuBarPresentationIfNeeded()
            self.usageNotificationService.evaluate(self.providerManager.quotaByProvider)
        }

        refreshService.configure { [weak self] in
            guard let self else { return }
            await self.providerManager.fetchAll()
            self.emitMenuBarPresentationIfNeeded()
        }

        refreshService.updateInterval(refreshIntervalSeconds)

        // Seed the staleness gate from the persisted quota cache so a
        // relaunch with fresh data doesn't fire a launch request.
        refreshService.lastRefreshDate = providerManager.latestFetchedAt

        // Watch for Claude Code session file changes. This fires constantly
        // while Claude Code is in active use, so it must go through the
        // staleness gate - an unconditional fetch here hammers the API.
        sessionWatcher.configure { [weak self] in
            await self?.refreshIfStale()
        }
        sessionWatcher.startWatching()

        hasFinishedInitialization = true
        emitMenuBarPresentationIfNeeded()
    }

    /// Initial data load. A fresh cache suppresses the launch request only
    /// when every active provider is represented in that cache.
    func initialLoad() async {
        let activeProviderIDs = Set(providerManager.activeProviders.map(\.id))
        let cachedProviderIDs = Set(providerManager.quotaByProvider.keys)
        if Self.shouldRefreshOnInitialLoad(
            lastRefresh: refreshService.lastRefreshDate,
            intervalSeconds: refreshIntervalSeconds,
            activeProviderIDs: activeProviderIDs,
            cachedProviderIDs: cachedProviderIDs
        ) {
            await refreshService.refresh()
        }
        emitMenuBarPresentationIfNeeded()
        await checkForUpdates()
    }

    /// Manual refresh triggered by user
    func manualRefresh() async {
        await refreshService.refresh()
        emitMenuBarPresentationIfNeeded()
        await checkForUpdates()
    }

    /// Passive refresh for popover opens and session file activity.
    /// Fetches only when data is older than the user's chosen interval, so
    /// automatic requests never exceed the configured cadence; in Manual
    /// only mode it never fetches.
    func refreshIfStale() async {
        let ageSeconds = refreshService.lastRefreshDate.map { Int(Date().timeIntervalSince($0)) } ?? -1
        let intervalSeconds = Int(refreshIntervalSeconds)
        guard Self.isDataStale(
            lastRefresh: refreshService.lastRefreshDate,
            intervalSeconds: refreshIntervalSeconds
        ) else {
            AppLog.refresh.info("passive trigger blocked: age \(ageSeconds)s < interval \(intervalSeconds)s")
            return
        }
        AppLog.refresh.info("passive trigger passed: age \(ageSeconds)s >= interval \(intervalSeconds)s")
        await refreshService.refresh()
        emitMenuBarPresentationIfNeeded()
    }

    nonisolated static func isDataStale(lastRefresh: Date?, intervalSeconds: Double, now: Date = Date()) -> Bool {
        guard intervalSeconds > 0 else { return false }
        guard let lastRefresh else { return true }
        return now.timeIntervalSince(lastRefresh) >= intervalSeconds
    }

    nonisolated static func shouldRefreshOnInitialLoad(
        lastRefresh: Date?,
        intervalSeconds: Double,
        activeProviderIDs: Set<String>,
        cachedProviderIDs: Set<String>,
        now: Date = Date()
    ) -> Bool {
        guard intervalSeconds > 0 else { return false }
        if !activeProviderIDs.isSubset(of: cachedProviderIDs) {
            return true
        }
        return isDataStale(
            lastRefresh: lastRefresh,
            intervalSeconds: intervalSeconds,
            now: now
        )
    }

    func toggleProvider(_ providerId: String) {
        providerManager.toggleProvider(providerId)
        emitMenuBarPresentationIfNeeded()
    }

    // MARK: - Menu Bar

    var menuBarPresentation: MenuBarPresentation {
        MenuBarPresentation.make(
            quotaByProvider: providerManager.quotaByProvider,
            showsPercentText: showPercentInMenuBar
        )
    }

    func emitMenuBarPresentationIfNeeded() {
        let presentation = menuBarPresentation
        guard presentation != lastMenuBarPresentation else { return }
        lastMenuBarPresentation = presentation
        onMenuBarPresentationChanged?(presentation)
    }

    // MARK: - Updates

    var currentAppVersion: String {
        let rawVersion =
            (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0.0.0"
        return rawVersion.lowercased().hasPrefix("v") ? String(rawVersion.dropFirst()) : rawVersion
    }

    func checkForUpdates(force: Bool = false) async {
        if installedUpdateVersion != nil { return }
        if isCheckingForUpdates { return }
        if !force,
           let lastCheck = lastUpdateCheckDate,
           Date().timeIntervalSince(lastCheck) < 3600 {
            return
        }

        isCheckingForUpdates = true
        defer {
            isCheckingForUpdates = false
            lastUpdateCheckDate = Date()
        }

        do {
            let latestRelease = try await appUpdateService.fetchLatestStableRelease()
            lastUpdateCheckError = nil

            if Self.isVersion(latestRelease.version, newerThan: currentAppVersion) {
                let isNewDiscovery = availableUpdateVersion != latestRelease.version
                availableRelease = latestRelease
                availableUpdateVersion = latestRelease.version
                availableUpdateURL = latestRelease.releaseURL
                if isNewDiscovery {
                    postUpdateNotification(version: latestRelease.version)
                }
            } else {
                availableRelease = nil
                availableUpdateVersion = nil
                availableUpdateURL = nil
            }
        } catch {
            if force {
                lastUpdateCheckError = error.localizedDescription
            }
        }
    }

    func installAvailableUpdate() async {
        guard let release = availableRelease, !isInstallingUpdate else { return }

        isInstallingUpdate = true
        updateInstallError = nil
        installedUpdateVersion = nil

        defer {
            isInstallingUpdate = false
        }

        do {
            try await appUpdateService.installRelease(release)
            installedUpdateVersion = release.version
            availableRelease = nil
            availableUpdateVersion = nil
            availableUpdateURL = nil
        } catch {
            updateInstallError = error.localizedDescription
        }
    }

    // MARK: - Update Notifications

    nonisolated static let updateActionIdentifier = "com.qdock.action.updateNow"
    private static let updateCategoryIdentifier = "com.qdock.category.update"

    /// Request notification permission and register the "Update Now" action.
    func setupUpdateNotifications() {
        guard NotificationCapability.isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let updateAction = UNNotificationAction(
            identifier: Self.updateActionIdentifier,
            title: "Update Now",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.updateCategoryIdentifier,
            actions: [updateAction],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    private func postUpdateNotification(version: String) {
        guard NotificationCapability.isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "QDock Update Available"
        content.body = "Version \(version) is ready to install."
        content.sound = .default
        content.categoryIdentifier = Self.updateCategoryIdentifier

        let request = UNNotificationRequest(
            identifier: "qdock-update-\(version)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let lhsParts = numericVersionParts(from: lhs)
        let rhsParts = numericVersionParts(from: rhs)
        let maxCount = max(lhsParts.count, rhsParts.count)

        for index in 0..<maxCount {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }

    private static func numericVersionParts(from version: String) -> [Int] {
        let parts = version.split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
        return parts.isEmpty ? [0] : parts
    }

}

private extension AppState {
    enum Keys {
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let showPercentInMenuBar = "showPercentInMenuBar"
        static let launchAtLogin = "launchAtLogin"
        static let usageAlertsEnabled = "usageAlertsEnabled"
        static let appearanceMode = "appearanceMode"
    }
}
