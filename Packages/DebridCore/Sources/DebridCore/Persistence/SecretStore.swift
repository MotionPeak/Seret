import Foundation
#if canImport(Security)
import Security
#endif

/// Stores a single opaque secret blob. Implementations key it however they like.
public protocol SecretStore: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func clear() throws
}

#if canImport(Security)
/// Keychain-backed generic-password store, keyed by `service` + `account`.
/// Mirrors `KeychainTokenStore`; verified on device (Keychain needs a host app).
public struct KeychainSecretStore: SecretStore {
    private let service: String
    private let account: String

    /// `service` namespaces the secret; `account` distinguishes multiple secrets under one
    /// service (defaults to "default" — callers with a single secret per service can omit it).
    public init(service: String, account: String = "default") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func read() throws -> Data? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        return out as? Data
    }

    public func write(_ data: Data) throws {
        try clear()
        var q = baseQuery
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

}
#endif

/// In-memory store for tests and previews.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Data?
    public init() {}
    public func read() throws -> Data? { lock.withLock { value } }
    public func write(_ data: Data) throws { lock.withLock { value = data } }
    public func clear() throws { lock.withLock { value = nil } }
}
