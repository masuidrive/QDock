import Foundation

/// Refreshes Claude OAuth access tokens using a refresh token.
///
/// Calls Claude Code's token endpoint using the same JSON request shape as
/// the installed CLI. Each successful refresh returns a new access token and
/// a new single-use refresh token.
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
    static let refreshUserAgent = "axios/1.15.2"
    static let defaultScopes = [
        "user:profile",
        "user:inference",
        "user:sessions:claude_code",
        "user:mcp_servers",
        "user:file_upload",
        "user:plugins",
    ]

    /// Exchange a refresh token for a fresh access + refresh token pair.
    func refresh(using refreshToken: String, scopes: [String]?) async throws -> RefreshedTokens {
        let request = try Self.makeRequest(refreshToken: refreshToken, scopes: scopes)
        return try await NetworkClient.shared.send(request, responseType: RefreshedTokens.self)
    }

    static func makeRequest(refreshToken: String, scopes: [String]?) throws -> URLRequest {
        let requestedScopes = scopes.flatMap { $0.isEmpty ? nil : $0 } ?? defaultScopes
        let jsonBody: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
            "scope": requestedScopes.joined(separator: " "),
        ]

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(refreshUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        return request
    }
}
