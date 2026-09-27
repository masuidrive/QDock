import XCTest
@testable import QDock

final class ProviderErrorTests: XCTestCase {
    func testOnlyAuthenticationFailuresRequireUserAttention() {
        XCTAssertTrue(ProviderManager.isAuthenticationError(
            ProviderError.authRequired("login required")
        ))
        XCTAssertTrue(ProviderManager.isAuthenticationError(ProviderError.tokenExpired))
        XCTAssertFalse(ProviderManager.isAuthenticationError(
            ProviderError.networkError(URLError(.notConnectedToInternet))
        ))
        XCTAssertFalse(ProviderManager.isAuthenticationError(
            ProviderError.apiError("temporarily unavailable")
        ))
        XCTAssertFalse(ProviderManager.isAuthenticationError(
            ProviderError.rateLimited(retryAfterSeconds: 60)
        ))
    }

    func testAuthenticationFailuresKeepCachedQuotaVisible() {
        XCTAssertFalse(ProviderManager.shouldClearCachedQuota(for: ProviderError.authRequired("login required")))
        XCTAssertFalse(ProviderManager.shouldClearCachedQuota(for: ProviderError.tokenExpired))
    }

    func testUnavailableProviderClearsCachedQuota() {
        XCTAssertTrue(ProviderManager.shouldClearCachedQuota(for: ProviderError.notInstalled))
        XCTAssertTrue(ProviderManager.shouldClearCachedQuota(for: ProviderError.notConfigured))
    }

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
