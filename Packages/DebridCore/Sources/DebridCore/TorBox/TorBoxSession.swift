import Foundation

public enum TorBoxSessionError: Error, Equatable, Sendable {
    case notSignedIn
}

/// Holds the TorBox account key. Unlike Real-Debrid there is nothing to refresh: the key is a
/// static bearer credential, so this is a thin wrapper over a `SecretStore`.
///
/// Never log or print the key.
public actor TorBoxSession: AccessTokenProviding {
    private let store: any SecretStore

    public init(store: any SecretStore) {
        self.store = store
    }

    #if canImport(Security)
    public static func keychain() -> TorBoxSession {
        TorBoxSession(store: KeychainSecretStore(service: "com.solomons.seret.torbox"))
    }
    #endif

    /// Saves the key. Surrounding whitespace is dropped (it rides in on a paste); a key that is
    /// empty after that reads back as signed out.
    public func establish(key: String) throws {
        try store.write(Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
    }

    public func validAccessToken() throws -> String {
        guard let key = Self.key(from: try store.read()) else { throw TorBoxSessionError.notSignedIn }
        return key
    }

    /// Reads the store each time, so a sign-out elsewhere is seen immediately. A store that
    /// cannot be read counts as signed out here; `validAccessToken()` is where the error surfaces.
    public var isSignedIn: Bool {
        Self.key(from: try? store.read()) != nil
    }

    public func signOut() throws {
        try store.clear()
    }

    private static func key(from data: Data?) -> String? {
        guard let data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }
}
