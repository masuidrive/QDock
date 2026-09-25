import XCTest
@testable import QDock

@MainActor
final class RefreshServiceTests: XCTestCase {
    func testApplyingDefaultIntervalStartsAutoRefreshWhenIdle() {
        let service = RefreshService()

        XCTAssertFalse(service.hasScheduledAutoRefresh)

        service.updateInterval(RefreshInterval.default.rawValue)

        XCTAssertTrue(service.hasScheduledAutoRefresh)
        service.stopAutoRefresh()
    }
}
