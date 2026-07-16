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

    func testDataOlderThanIntervalIsStale() {
        XCTAssertTrue(AppState.isDataStale(
            lastRefresh: now.addingTimeInterval(-180), intervalSeconds: 180, now: now
        ))
        XCTAssertTrue(AppState.isDataStale(
            lastRefresh: now.addingTimeInterval(-3600), intervalSeconds: 180, now: now
        ))
    }
}
