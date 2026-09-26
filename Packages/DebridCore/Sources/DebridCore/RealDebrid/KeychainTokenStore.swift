#if canImport(Security)
import Foundation
import Security

public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}

/// Stores the credentials JSON blob as a generic-password Keychain item.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    public init(service: String = "com.solomons.seret.realdebrid",
                account: String = "credentials") {
        self.service = service
        self.account = account
    }

    public func load() throws -> StoredCredentials? {
        var item: CFTypeRef?
        let status = KeychainQuery.perform(service: service, account: account) { base in
            var query = base
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            item = nil
            return SecItemCopyMatching(query as CFDictionary, &item)
        }
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        return try JSONDecoder().decode(StoredCredentials.self, from: data)
    }

    public func save(_ credentials: StoredCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let status = KeychainQuery.perform(service: service, account: account) { base in
            let updateStatus = SecItemUpdate(base as CFDictionary,
                                             [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecItemNotFound else { return updateStatus }
            var addQuery = base
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(addQuery as CFDictionary, nil)
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
