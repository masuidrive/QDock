import XCTest
@testable import QDock

final class ProviderErrorTests: XCTestCase {
    func testRateLimitedMessageIncludesRetryAfterMinutes() {
        let error = ProviderError.rateLimited(retryAfterSeconds: 889)
        XCTAssertEqual(error.errorDescription, "Rate limited by the API. Retrying in ~15m.")
    }

    func testRateLimitedMessageRoundsUpToAtLeastOneMinute() {
        let error = ProviderError.rateLimited(retryAfterSeconds: 20)
        XCTAssertEqual(error.errorDescription, "Rate limited by the API. Retrying in ~1m.")
    }

    func testRateLimitedMessageWithoutRetryAfterStaysGeneric() {
        let error = ProviderError.rateLimited()
        XCTAssertEqual(error.errorDescription, "Rate limited. Please wait a moment and try again.")
    }
}
