import XCTest
@testable import QDock

final class ClaudeCredentialRecoveryTests: XCTestCase {
    func testExpiredCredentialWithRefreshTokenCanRecover() {
        let oauth = ClaudeOAuthCredentials.OAuthData(
            accessToken: "expired-access",
            refreshToken: "refresh-token",
            expiresAt: 0,
            scopes: ["user:profile"],
            subscriptionType: "max",
            rateLimitTier: nil
        )

        let resolution = ClaudeCredentialResolver.resolve(
            fileOAuth: nil,
            keychainOAuth: oauth,
            manualToken: nil
        )

        guard case .refreshRequired(let refreshToken) = resolution else {
            return XCTFail("An expired access token with a refresh token must be recoverable")
        }
        XCTAssertEqual(refreshToken, "refresh-token")
    }

    func testExpiredCredentialWithoutRefreshTokenIsUnavailable() {
        let oauth = ClaudeOAuthCredentials.OAuthData(
            accessToken: "expired-access",
            refreshToken: nil,
            expiresAt: 0,
            scopes: ["user:profile"],
            subscriptionType: "max",
            rateLimitTier: nil
        )

        let resolution = ClaudeCredentialResolver.resolve(
            fileOAuth: nil,
            keychainOAuth: oauth,
            manualToken: nil
        )

        guard case .unavailable = resolution else {
            return XCTFail("A credential without a usable access or refresh token must be unavailable")
        }
    }

    func testRefreshedKeychainCredentialPreservesClaudeMetadata() throws {
        let existing = Data(
            """
            {
              "primaryApiKey": null,
              "claudeAiOauth": {
                "accessToken": "old-access",
                "refreshToken": "old-refresh",
                "expiresAt": 1,
                "refreshTokenExpiresAt": 9999999999999,
                "scopes": ["user:profile", "user:inference"],
                "subscriptionType": "max"
              }
            }
            """.utf8
        )

        let updated = try XCTUnwrap(
            ClaudeKeychainReader.mergingRefreshedCredentials(
                in: existing,
                replacingRefreshToken: "old-refresh",
                accessToken: "new-access",
                refreshToken: "new-refresh",
                expiresAt: 123456789
            )
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: updated) as? [String: Any]
        )
        let oauth = try XCTUnwrap(json["claudeAiOauth"] as? [String: Any])

        XCTAssertEqual(oauth["accessToken"] as? String, "new-access")
        XCTAssertEqual(oauth["refreshToken"] as? String, "new-refresh")
        XCTAssertEqual(oauth["expiresAt"] as? Int, 123456789)
        XCTAssertEqual(oauth["refreshTokenExpiresAt"] as? Int64, 9_999_999_999_999)
        XCTAssertEqual(oauth["scopes"] as? [String], ["user:profile", "user:inference"])
        XCTAssertEqual(oauth["subscriptionType"] as? String, "max")
    }

    func testRefreshedKeychainCredentialRejectsConcurrentRotation() {
        let existing = Data(
            """
            {
              "claudeAiOauth": {
                "accessToken": "newer-access",
                "refreshToken": "newer-refresh",
                "expiresAt": 9999999999999
              }
            }
            """.utf8
        )

        let updated = ClaudeKeychainReader.mergingRefreshedCredentials(
            in: existing,
            replacingRefreshToken: "stale-refresh",
            accessToken: "our-access",
            refreshToken: "our-refresh",
            expiresAt: 123456789
        )

        XCTAssertNil(updated, "Do not overwrite credentials rotated by another Claude process")
    }
}
