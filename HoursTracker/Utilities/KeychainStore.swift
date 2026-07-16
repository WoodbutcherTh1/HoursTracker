import Foundation
import Security
import os

/// Minimal Keychain wrapper (Security framework only). Used for the national ID number.
enum KeychainStore {
    enum Key: String {
        case workerIDNumber = "workerIDNumber"
    }

    private static let service = "com.hourstracker.app"
    private static let logger = Logger(subsystem: "com.hourstracker.app", category: "keychain")

    static func setString(_ value: String, for key: Key) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)

        guard !value.isEmpty else { return }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Keychain set failed: \(status, privacy: .private)")
            throw KeychainStoreError.unhandledStatus(status)
        }
    }

    static func string(for key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed: \(status, privacy: .private)")
            throw KeychainStoreError.unhandledStatus(status)
        }
    }
}

enum KeychainStoreError: Error {
    case unhandledStatus(OSStatus)
}
