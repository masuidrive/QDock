import SwiftUI

/// Main dashboard view shown in the popover
struct DashboardView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            if appState.providerManager.activeProviders.isEmpty {
                EmptyStateView {
                    appState.showingSettings = true
                }
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        // Total summary
                        UsageSummaryView(appState: appState)

                        Divider()
                            .padding(.horizontal)

                        // Provider rows
                        ForEach(appState.providerManager.activeProviders, id: \.id) { provider in
                            ProviderRowView(
                                provider: provider,
                                usage: appState.providerManager.usageByProvider[provider.id],
                                error: appState.providerManager.errorsByProvider[provider.id],
                                isLoading: appState.providerManager.loadingProviders.contains(provider.id)
                            ) {
                                appState.selectedProvider = provider
                            }
                        }

                        // Trend chart (if data available)
                        if !allDailyTrends.isEmpty {
                            Divider()
                                .padding(.horizontal)
                            TrendChartView(dailyData: allDailyTrends)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }

            Divider()

            // Footer
            footerView
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("UsageBar")
                    .font(.headline)

                if let lastRefresh = appState.refreshService.timeSinceLastRefresh {
                    Text("Updated \(lastRefresh)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Period picker
            Picker("", selection: $appState.providerManager.selectedPeriod) {
                ForEach(UsagePeriod.allCases) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
            .onChange(of: appState.providerManager.selectedPeriod) { _, _ in
                Task { await appState.manualRefresh() }
            }

            RefreshButton(isRefreshing: appState.refreshService.isRefreshing) {
                Task { await appState.manualRefresh() }
            }

            Button {
                appState.showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button("Quit UsageBar") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Text("v1.0.0")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var allDailyTrends: [DailyUsage] {
        appState.providerManager.usageByProvider.values
            .flatMap { $0.dailyTrend }
            .sorted { $0.date < $1.date }
    }
}
