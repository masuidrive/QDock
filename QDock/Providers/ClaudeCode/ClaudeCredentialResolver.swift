import Foundation

struct ClaudeResolvedAccessToken {
    let token: String
    let scopes: [String]?
    let refreshToken: String?
}

enum ClaudeCredentialResolution {
    case accessToken(ClaudeResolvedAccessToken)
    case refreshRequired(String)
    case unavailable
}

/// Chooses a Claude credential without performing I/O.
/// Valid access tokens win; a refresh token is surfaced only when no usable
/// access token or manually supplied token remains.
struct ClaudeCredentialResolver {
    static func resolve(
        fileOAuth: ClaudeOAuthCredentials.OAuthData?,
        keychainOAuth: ClaudeOAuthCredentials.OAuthData?,
        manualToken: String?
    ) -> ClaudeCredentialResolution {
        for oauth in [fileOAuth, keychainOAuth] {
            if let oauth,
               !oauth.isExpired,
               let token = nonEmpty(oauth.accessToken) {
                return .accessToken(
                    ClaudeResolvedAccessToken(
                        token: token,
                        scopes: oauth.scopes,
                        refreshToken: nonEmpty(oauth.refreshToken)
                    )
                )
            }
        }

        if let manualToken = nonEmpty(manualToken) {
            return .accessToken(
                ClaudeResolvedAccessToken(
                    token: manualToken,
                    scopes: nil,
                    refreshToken: nil
                )
            )
        }

        for oauth in [fileOAuth, keychainOAuth] {
            if let refreshToken = nonEmpty(oauth?.refreshToken) {
                return .refreshRequired(refreshToken)
            }
        }

        return .unavailable
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
