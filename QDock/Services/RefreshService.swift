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

    var refreshInterval: TimeInterval = 120 // 2 minutes default

    func configure(onRefresh: @escaping () async -> Void) {
        self.onRefresh = onRefresh
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        guard refreshInterval > 0 else { return }

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.refreshInterval ?? 120))
                guard !Task.isCancelled else { break }
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
            guard wedged else { return }
        }
        isRefreshing = true
        refreshStartedAt = Date()
        error = nil

        await onRefresh?()

        lastRefreshDate = Date()
        isRefreshing = false
        refreshStartedAt = nil
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

/// Available refresh interval options
enum RefreshInterval: Double, CaseIterable, Identifiable {
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case manual = 0

    var id: Double { rawValue }

    var displayName: String {
        switch self {
        case .oneMinute: return "1 minute"
        case .twoMinutes: return "2 minutes"
        case .fiveMinutes: return "5 minutes"
        case .manual: return "Manual only"
        }
    }
}
