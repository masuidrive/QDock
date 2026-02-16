import Foundation
import Combine

/// Manages periodic auto-refresh of usage data
@MainActor
final class RefreshService: ObservableObject {
    @Published var isRefreshing = false
    @Published var lastRefreshDate: Date?
    @Published var error: String?

    private var refreshTask: Task<Void, Never>?
    private var onRefresh: (() async -> Void)?

    var refreshInterval: TimeInterval = 900 // 15 minutes default

    func configure(onRefresh: @escaping () async -> Void) {
        self.onRefresh = onRefresh
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        guard refreshInterval > 0 else { return }

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.refreshInterval ?? 900))
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
        guard !isRefreshing else { return }
        isRefreshing = true
        error = nil

        await onRefresh?()

        lastRefreshDate = Date()
        isRefreshing = false
    }

    func updateInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        if interval > 0 {
            startAutoRefresh()
        } else {
            stopAutoRefresh()
        }
    }

    var timeSinceLastRefresh: String? {
        guard let date = lastRefreshDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Available refresh interval options
enum RefreshInterval: Double, CaseIterable, Identifiable {
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    case oneHour = 3600
    case manual = 0

    var id: Double { rawValue }

    var displayName: String {
        switch self {
        case .fiveMinutes: return "5 minutes"
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .manual: return "Manual only"
        }
    }
}
