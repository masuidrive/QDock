import Foundation
import Observation

/// Manages periodic auto-refresh of usage data
@Observable
@MainActor
final class RefreshService {
    var isRefreshing = false
    var lastRefreshDate: Date?
    var error: String?

    @ObservationIgnored
    private var refreshStartedAt: Date?
    /// A refresh "running" longer than this is considered wedged; the guard
    /// stops blocking so auto-refresh can never die silently.
    private static let wedgedRefreshThreshold: TimeInterval = 120

    private var refreshTask: Task<Void, Never>?
    private var onRefresh: (() async -> Void)?
    @ObservationIgnored
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var refreshInterval: TimeInterval = RefreshInterval.default.rawValue

    func configure(onRefresh: @escaping () async -> Void) {
        self.onRefresh = onRefresh
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        guard refreshInterval > 0 else { return }

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.refreshInterval ?? RefreshInterval.default.rawValue))
                guard !Task.isCancelled else { break }
                AppLog.refresh.info("timer tick")
                await self?.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        if isRefreshing {
            let wedged = refreshStartedAt.map {
                Date().timeIntervalSince($0) > Self.wedgedRefreshThreshold
            } ?? true
            guard wedged else {
                AppLog.refresh.info("refresh skipped: already in flight")
                return
            }
            AppLog.refresh.warning("refresh proceeding past wedged in-flight refresh")
        }
        AppLog.refresh.info("refresh start")
        isRefreshing = true
        refreshStartedAt = Date()
        error = nil

        await onRefresh?()

        lastRefreshDate = Date()
        isRefreshing = false
        refreshStartedAt = nil
        AppLog.refresh.info("refresh done")
    }

    func updateInterval(_ interval: TimeInterval) {
        guard interval != refreshInterval else { return }
        refreshInterval = interval
        if interval > 0 {
            startAutoRefresh()
        } else {
            stopAutoRefresh()
        }
    }

    var timeSinceLastRefresh: String? {
        guard let date = lastRefreshDate else { return nil }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Available refresh interval options.
/// Minimum is 3 minutes: the usage API tolerates ~180s polling at best, and
/// Claude Code itself shares the same token's request budget, so anything
/// faster risks escalating 429 penalties.
enum RefreshInterval: Double, CaseIterable, Identifiable {
    case threeMinutes = 180
    case fiveMinutes = 300
    case tenMinutes = 600
    case manual = 0

    static let `default`: RefreshInterval = .fiveMinutes

    /// Smallest selectable auto-refresh interval, in seconds.
    static let minimumAutoSeconds: Double = RefreshInterval.threeMinutes.rawValue

    var id: Double { rawValue }

    /// Maps any previously stored value onto a currently offered option:
    /// 0 stays Manual; anything else snaps up to the nearest allowed
    /// interval so removed/faster options can never come back via defaults.
    static func normalized(fromStored value: Double) -> Double {
        guard value > 0 else { return manual.rawValue }
        let autoOptions = allCases.map(\.rawValue).filter { $0 > 0 }.sorted()
        return autoOptions.first { $0 >= value } ?? autoOptions.last ?? RefreshInterval.default.rawValue
    }

    var displayName: String {
        switch self {
        case .threeMinutes: return "3 minutes"
        case .fiveMinutes: return "5 minutes"
        case .tenMinutes: return "10 minutes"
        case .manual: return "Manual only"
        }
    }
}
