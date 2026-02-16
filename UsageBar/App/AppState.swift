import Foundation
import SwiftUI

/// Central application state managing providers, refresh, and navigation
@MainActor
final class AppState: ObservableObject {
    @Published var providerManager = ProviderManager()
    @Published var refreshService = RefreshService()
    @Published var selectedProvider: (any UsageProvider)?
    @Published var showingSettings = false
    @Published var showCostInMenuBar = false

    // User preferences
    @AppStorage("refreshIntervalSeconds") var refreshIntervalSeconds: Double = 900
    @AppStorage("showCostInMenuBarPref") var showCostInMenuBarPref: Bool = false
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false

    init() {
        showCostInMenuBar = showCostInMenuBarPref

        refreshService.configure { [weak self] in
            await self?.providerManager.fetchAll()
        }

        refreshService.updateInterval(refreshIntervalSeconds)
    }

    /// Initial data load
    func initialLoad() async {
        await refreshService.refresh()
    }

    /// Manual refresh triggered by user
    func manualRefresh() async {
        await refreshService.refresh()
    }

    /// Menu bar display text
    var menuBarText: String? {
        guard showCostInMenuBar else { return nil }
        let cost = providerManager.totalCost
        if cost > 0 {
            return formatCost(cost)
        }
        return nil
    }

    /// Format a cost value for display
    func formatCost(_ cost: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: cost as NSDecimalNumber) ?? "$0.00"
    }

    /// Format token count for display
    func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
