import XCTest
@testable import QDock

/// Staleness gate for passive refresh triggers (popover open, session file
/// activity): automatic fetches must never exceed the user's chosen interval.
final class AppStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNeverStaleInManualOnlyMode() {
        XCTAssertFalse(AppState.isDataStale(lastRefresh: nil, intervalSeconds: 0, now: now))
        XCTAssertFalse(AppState.isDataStale(
            lastRefresh: now.addingTimeInterval(-9999), intervalSeconds: 0, now: now
        ))
    }

    func testStaleWhenNeverRefreshed() {
        XCTAssertTrue(AppState.isDataStale(lastRefresh: nil, intervalSeconds: 180, now: now))
    }

    func testFreshDataWithinIntervalIsNotStale() {
        XCTAssertFalse(AppState.isDataStale(
            lastRefresh: now.addingTimeInterval(-60), intervalSeconds: 180, now: now
        ))
    }

    func testStoredIntervalSnapsToOfferedOptions() {
        XCTAssertEqual(RefreshInterval.normalized(fromStored: 0), 0, "Manual stays manual")
        XCTAssertEqual(RefreshInterval.normalized(fromStored: 60), 180, "Removed 1m snaps up to 3m")
        XCTAssertEqual(RefreshInterval.normalized(fromStored: 120), 180, "Removed 2m snaps up to 3m")
        XCTAssertEqual(RefreshInterval.normalized(fromStored: 240), 300, "Removed 4m snaps up to 5m")
        XCTAssertEqual(RefreshInterval.normalized(fromStored: 300), 300, "Existing option kept")
        XCTAssertEqual(RefreshInterval.normalized(fromStored: 9999), 600, "Above max snaps down to 10m")
    }

    func testDataOlderThanIntervalIsStale() {
        XCTAssertTrue(AppState.isDataStale(
            lastRefresh: now.addingTimeInterval(-180), intervalSeconds: 180, now: now
        ))
        XCTAssertTrue(AppState.isDataStale(
            lastRefresh: now.addingTimeInterval(-3600), intervalSeconds: 180, now: now
        ))
    }

    func testMenuBarPresentationOrdersClaudeThenCodex() {
        let quotas = [
            "codex": makeQuota(id: "codex", provider: "Codex", percent: 19),
            "claude-code": makeQuota(
                id: "claude-code",
                provider: "Claude",
                percent: 4,
                weeklyPercent: 33
            ),
        ]

        let presentation = MenuBarPresentation.make(
            quotaByProvider: quotas,
            showsPercentText: true
        )

        XCTAssertEqual(presentation.usages.map(\.provider), [.claude, .codex])
        XCTAssertEqual(presentation.usages.map(\.roundedPercent), [33, 19])
        XCTAssertTrue(presentation.showsPercentText)
    }

    func testMenuBarPresentationKeepsSingleAvailableProvider() throws {
        let presentation = MenuBarPresentation.make(
            quotaByProvider: [
                "codex": makeQuota(id: "codex", provider: "Codex", percent: 19),
            ],
            showsPercentText: false
        )

        let usage = try XCTUnwrap(presentation.usages.first)
        XCTAssertEqual(presentation.usages.count, 1)
        XCTAssertEqual(usage.provider, .codex)
        XCTAssertEqual(usage.roundedPercent, 19)
        XCTAssertFalse(presentation.showsPercentText)
    }

    private func makeQuota(
        id: String,
        provider: String,
        percent: Double,
        weeklyPercent: Double? = nil
    ) -> QuotaData {
        var windows = [
            QuotaWindow(
                id: "session",
                displayName: "Session",
                usagePercent: percent,
                resetsAt: nil,
                windowDurationMinutes: 300
            )
        ]
        if let weeklyPercent {
            windows.append(QuotaWindow(
                id: "weekly",
                displayName: "Weekly",
                usagePercent: weeklyPercent,
                resetsAt: nil,
                windowDurationMinutes: 10_080
            ))
        }

        return QuotaData(
            id: id,
            provider: provider,
            planName: nil,
            windows: windows,
            accountEmail: nil,
            fetchedAt: now,
            isStale: false
        )
    }
}
