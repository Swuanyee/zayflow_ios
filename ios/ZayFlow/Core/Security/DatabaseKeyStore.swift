import Foundation
import Security

enum DatabaseKeyStoreError: Error {
    case keychain(OSStatus)
    case randomGeneration(OSStatus)
}

struct DatabaseKeyStore: Sendable {
    private let service = "com.zayflow.pos.database"
    private let account = "operational-database-key-v1"

    func loadOrCreate() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return data
        }
        guard status == errSecItemNotFound else {
            throw DatabaseKeyStoreError.keychain(status)
        }

        var key = Data(count: 32)
        let randomStatus = key.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw DatabaseKeyStoreError.randomGeneration(randomStatus)
        }

        let insertion: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: key
        ]
        let insertionStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard insertionStatus == errSecSuccess else {
            throw DatabaseKeyStoreError.keychain(insertionStatus)
        }
        return key
    }
}
