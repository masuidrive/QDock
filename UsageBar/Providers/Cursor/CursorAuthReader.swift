import Foundation
import SQLite3

/// Reads Cursor IDE authentication credentials from the local SQLite database
/// Data lives in: ~/Library/Application Support/Cursor/User/globalStorage/state.vscdb
final class CursorAuthReader {

    /// Cursor data directory on macOS
    static var dataDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor")
    }

    /// Path to the state database
    static var stateDBPath: URL {
        dataDir
            .appendingPathComponent("User/globalStorage/state.vscdb")
    }

    /// Check if Cursor is installed
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: dataDir.path)
    }

    /// Read the access token from state.vscdb
    static var accessToken: String? {
        readFromDB(key: "cursorAuth/accessToken")
    }

    /// Read the refresh token
    static var refreshToken: String? {
        readFromDB(key: "cursorAuth/refreshToken")
    }

    /// Extract user ID from the JWT access token
    static var userId: String? {
        guard let token = accessToken else { return nil }
        return decodeJWTSubject(token)
    }

    /// Build the session cookie for cursor.com API calls
    static var sessionCookie: String? {
        guard let userId = userId, let token = accessToken else { return nil }
        let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userId
        let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        return "WorkosCursorSessionToken=\(encodedUserId)%3A%3A\(encodedToken)"
    }

    // MARK: - Private

    /// Read a value from the SQLite ItemTable
    private static func readFromDB(key: String) -> String? {
        let path = stateDBPath.path
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let query = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1"
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, key, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        guard let cStr = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cStr)
    }

    /// Decode the `sub` claim from a JWT without verification
    private static func decodeJWTSubject(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
        // Base64URL → Base64
        payload = payload.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Pad
        while payload.count % 4 != 0 {
            payload.append("=")
        }

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String else {
            return nil
        }

        return sub
    }
}
