import Foundation
import Security

/// Manages secure storage of API keys in macOS Keychain
final class KeychainService {
    static let shared = KeychainService()

    private let servicePrefix = "com.qdock"
    private let legacyServicePrefix = "com.usagebar"

    private init() {}

    /// Save an API key to the Keychain
    func save(key: String, value: String) throws {
        let data = Data(value.utf8)
        let service = "\(servicePrefix).\(key)"

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Retrieve an API key from the Keychain
    func get(key: String) -> String? {
        let service = "\(servicePrefix).\(key)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }

        // Backward compatibility for pre-rename installs.
        let legacyService = "\(legacyServicePrefix).\(key)"
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var legacyResult: AnyObject?
        let legacyStatus = SecItemCopyMatching(legacyQuery as CFDictionary, &legacyResult)
        guard legacyStatus == errSecSuccess, let legacyData = legacyResult as? Data else {
            return nil
        }

        return String(data: legacyData, encoding: .utf8)
    }

    /// Delete an API key from the Keychain
    func delete(key: String) {
        let service = "\(servicePrefix).\(key)"
        let legacyService = "\(legacyServicePrefix).\(key)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: key,
        ]

        SecItemDelete(query as CFDictionary)
        SecItemDelete(legacyQuery as CFDictionary)
    }

    /// Check if a key exists in the Keychain
    func exists(key: String) -> Bool {
        get(key: key) != nil
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to Keychain (status: \(status))"
        }
    }
}
