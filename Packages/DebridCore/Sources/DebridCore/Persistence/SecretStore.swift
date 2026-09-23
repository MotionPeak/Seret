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

    public func read() throws -> Data? {
        var out: CFTypeRef?
        let status = KeychainQuery.perform(service: service, account: account) { base in
            var query = base
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            out = nil
            return SecItemCopyMatching(query as CFDictionary, &out)
        }
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        return out as? Data
    }

    public func write(_ data: Data) throws {
        try clear()
        let status = KeychainQuery.perform(service: service, account: account) { base in
            var query = base
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public func clear() throws {
        let status = KeychainQuery.perform(service: service, account: account) {
            SecItemDelete($0 as CFDictionary)
        }
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
