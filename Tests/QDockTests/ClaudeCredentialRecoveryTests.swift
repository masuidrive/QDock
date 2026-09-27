import XCTest
@testable import QDock

final class ClaudeCredentialRecoveryTests: XCTestCase {
    func testTokenRefreshUsesCurrentClaudeCodeOAuthConfiguration() {
        XCTAssertEqual(
            ClaudeTokenRefresher.tokenURL.absoluteString,
            "https://platform.claude.com/v1/oauth/token"
        )
        XCTAssertEqual(
            ClaudeTokenRefresher.clientID,
            "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
        )
    }

    func testTokenRefreshRequestMatchesCurrentClaudeCodeWireFormat() throws {
        let request = try ClaudeTokenRefresher.makeRequest(
            refreshToken: "test-refresh-token",
            scopes: ["user:profile", "user:inference"]
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json, text/plain, */*")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "axios/1.15.2")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: String]
        )
        XCTAssertEqual(json["grant_type"], "refresh_token")
        XCTAssertEqual(json["refresh_token"], "test-refresh-token")
        XCTAssertEqual(json["client_id"], ClaudeTokenRefresher.clientID)
        XCTAssertEqual(json["scope"], "user:profile user:inference")
    }

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

        guard case .refreshRequired(let credential) = resolution else {
            return XCTFail("An expired access token with a refresh token must be recoverable")
        }
        XCTAssertEqual(credential.refreshToken, "refresh-token")
        XCTAssertEqual(credential.scopes, ["user:profile"])
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

    func testRefreshedCredentialPreservesSnakeCaseFileShape() throws {
        let existing = Data(
            """
            {
              "claude_ai_oauth": {
                "access_token": "old-access",
                "refresh_token": "old-refresh",
                "expires_at": 1,
                "scopes": ["user:profile"]
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
        let oauth = try XCTUnwrap(json["claude_ai_oauth"] as? [String: Any])

        XCTAssertEqual(oauth["access_token"] as? String, "new-access")
        XCTAssertEqual(oauth["refresh_token"] as? String, "new-refresh")
        XCTAssertEqual(oauth["expires_at"] as? Int, 123456789)
        XCTAssertNil(oauth["accessToken"], "Do not change the credential file's schema")
    }
}
