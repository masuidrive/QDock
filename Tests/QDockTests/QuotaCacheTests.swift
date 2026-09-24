import XCTest
@testable import QDock

final class QuotaCacheTests: XCTestCase {
    func testQuotaDataCodableRoundtrip() throws {
        let quota = QuotaData(
            id: "claude-code",
            provider: "Claude",
            planName: "Max 5x",
            windows: [
                QuotaWindow(
                    id: "session",
                    displayName: "Session (5h)",
                    usagePercent: 42.5,
                    resetsAt: Date(timeIntervalSince1970: 1_800_000_000),
                    windowDurationMinutes: 300,
                    severity: "warning",
                    isActive: true
                )
            ],
            accountEmail: "user@example.com",
            fetchedAt: Date(timeIntervalSince1970: 1_799_999_000),
            isStale: false,
            usageCredits: UsageCreditsInfo(
                usedCredits: 1.5, monthlyLimit: 10, utilization: 15, currency: "USD"
            )
        )

        let data = try JSONEncoder().encode(["claude-code": quota])
        let decoded = try JSONDecoder().decode([String: QuotaData].self, from: data)

        let roundtripped = try XCTUnwrap(decoded["claude-code"])
        XCTAssertEqual(roundtripped.fetchedAt, quota.fetchedAt)
        XCTAssertEqual(roundtripped.planName, "Max 5x")
        XCTAssertEqual(roundtripped.windows, quota.windows)
        XCTAssertEqual(roundtripped.usageCredits, quota.usageCredits)
    }

    func testParseCLIVersion() {
        XCTAssertEqual(ClaudeCodeDetector.parseCLIVersion(from: "2.1.7 (Claude Code)\n"), "2.1.7")
        XCTAssertEqual(ClaudeCodeDetector.parseCLIVersion(from: "claude v10.0.12"), "10.0.12")
        XCTAssertNil(ClaudeCodeDetector.parseCLIVersion(from: "command not found"))
    }

    func testWindowTimeProgressIsOneSeventhAfterOneDay() throws {
        let monday = Date(timeIntervalSince1970: 1_800_000_000)
        let nextMonday = monday.addingTimeInterval(7 * 24 * 60 * 60)
        let tuesday = monday.addingTimeInterval(24 * 60 * 60)
        let window = QuotaWindow(
            id: "weekly",
            displayName: "Weekly",
            usagePercent: 20,
            resetsAt: nextMonday,
            windowDurationMinutes: 7 * 24 * 60
        )

        XCTAssertEqual(
            try XCTUnwrap(window.timeProgressPercent(at: tuesday)),
            100.0 / 7.0,
            accuracy: 0.000_001
        )
    }

    func testWindowTimeProgressClampsToWindowBounds() throws {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let window = QuotaWindow(
            id: "session",
            displayName: "Session",
            usagePercent: 20,
            resetsAt: reset,
            windowDurationMinutes: 300
        )

        XCTAssertEqual(
            try XCTUnwrap(window.timeProgressPercent(at: reset.addingTimeInterval(-301 * 60))),
            0
        )
        XCTAssertEqual(
            try XCTUnwrap(window.timeProgressPercent(at: reset.addingTimeInterval(60))),
            100
        )
    }

    func testWindowTimeProgressRequiresResetAndPositiveDuration() {
        let noReset = QuotaWindow(
            id: "weekly",
            displayName: "Weekly",
            usagePercent: 20,
            resetsAt: nil,
            windowDurationMinutes: 10_080
        )
        let invalidDuration = QuotaWindow(
            id: "weekly",
            displayName: "Weekly",
            usagePercent: 20,
            resetsAt: Date(),
            windowDurationMinutes: 0
        )

        XCTAssertNil(noReset.timeProgressPercent(at: Date()))
        XCTAssertNil(invalidDuration.timeProgressPercent(at: Date()))
    }

    @MainActor
    func testSevenDayWindowUsesWeekLabelEvenWhenProviderCallsItSession() {
        let window = QuotaWindow(
            id: "session",
            displayName: "Session",
            usagePercent: 20,
            resetsAt: Date(),
            windowDurationMinutes: 7 * 24 * 60
        )

        XCTAssertEqual(DashboardView.siteLabel(for: window), "Week")
    }
}
