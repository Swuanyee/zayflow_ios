import Foundation
import Security

enum LoginMode: String, CaseIterable, Codable, Identifiable {
    case organisationDashboard = "organisation_dashboard"
    case pos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .organisationDashboard: "Organisation Dashboard"
        case .pos: "POS"
        }
    }
}

enum UserRole: String, Codable {
    case owner
    case admin
    case manager
    case cashier

    var canUseOrganisationDashboard: Bool {
        switch self {
        case .owner, .admin, .manager: true
        case .cashier: false
        }
    }
}

struct AuthSession: Codable, Equatable, Sendable {
    struct Organization: Codable, Equatable, Sendable {
        let id: UUID
        let code: String
        let name: String
    }

    struct Shop: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        let code: String
        let name: String
    }

    struct User: Codable, Equatable, Sendable {
        let id: UUID
        let userCode: String
        let displayName: String
        let role: UserRole
        let canSell: Bool
        let canIntake: Bool
    }

    struct Device: Codable, Equatable, Sendable {
        let installationId: String
        let requiresFullSyncBy: Date
    }

    let mode: LoginMode
    let organization: Organization
    let shop: Shop?
    let user: User
    let permittedShops: [Shop]
    let device: Device
    let issuedAt: Date

    var isSyncOverdue: Bool { Date() >= device.requiresFullSyncBy }
    var canWriteOrganisationDashboard: Bool { user.role.canUseOrganisationDashboard && !isSyncOverdue }
}

enum SessionStoreError: Error {
    case keychain(OSStatus)
}

struct SessionStore: Sendable {
    private let service = "com.zayflow.pos.auth"
    private let account = "active-session-v1"

    func load() throws -> AuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SessionStoreError.keychain(status)
        }
        return try JSONDecoder.zayFlow.decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession) throws {
        let data = try JSONEncoder.zayFlow.encode(session)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw SessionStoreError.keychain(status) }

        var insertion = query
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        insertion[kSecValueData as String] = data
        let insertionStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard insertionStatus == errSecSuccess else { throw SessionStoreError.keychain(insertionStatus) }
    }

    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SessionStoreError.keychain(status) }
    }
}

extension JSONEncoder {
    static var zayFlow: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var zayFlow: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
