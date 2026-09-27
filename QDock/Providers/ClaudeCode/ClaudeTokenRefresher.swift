import Foundation

/// Refreshes Claude OAuth access tokens using a refresh token.
///
/// Calls `POST https://platform.claude.com/v1/oauth/token` with
/// `grant_type=refresh_token`. Each successful refresh returns a new
/// access token (and a new single-use refresh token).
struct ClaudeTokenRefresher {

    struct RefreshedTokens: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int       // seconds until access token expires
    }

    /// The client_id registered for Claude Code OAuth.
    /// This is a public identifier (not a secret) — same value hardcoded in Claude Code CLI.
    /// Source: https://github.com/anthropics/claude-code/issues/47754
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!

    /// Exchange a refresh token for a fresh access + refresh token pair.
    /// The token endpoint rate limits like the usage endpoint, so it gets
    /// the same claude-code User-Agent.
    func refresh(using refreshToken: String, userAgent: String) async throws -> RefreshedTokens {
        let formBody: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ]

        return try await NetworkClient.shared.post(
            url: Self.tokenURL,
            headers: ["User-Agent": userAgent],
            formBody: formBody,
            responseType: RefreshedTokens.self
        )
    }
}
