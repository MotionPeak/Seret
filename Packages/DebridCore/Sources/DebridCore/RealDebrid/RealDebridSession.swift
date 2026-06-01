import Foundation

public enum RealDebridSessionError: Error, Equatable {
    case notSignedIn
}

/// Owns the RD credential lifecycle: serves a valid access token, refreshing
/// transparently when the current one is within `refreshSkew` of expiry.
public actor RealDebridSession {
    private let auth: RealDebridAuthClient
    private let store: TokenStore
    private let now: @Sendable () -> Date
    private let refreshSkew: TimeInterval

    private var cached: StoredCredentials?

    public init(auth: RealDebridAuthClient = .init(),
                store: TokenStore,
                now: @escaping @Sendable () -> Date = { Date() },
                refreshSkew: TimeInterval = 60) {
        self.auth = auth
        self.store = store
        self.now = now
        self.refreshSkew = refreshSkew
    }

    /// Persist a freshly completed device-code login.
    public func establish(token: RDToken, deviceCredentials: RDDeviceCredentials) throws {
        let creds = StoredCredentials(token: token, deviceCredentials: deviceCredentials, obtainedAt: now())
        try store.save(creds)
        cached = creds
    }

    public func validAccessToken() async throws -> String {
        guard let creds = try currentCredentials() else { throw RealDebridSessionError.notSignedIn }
        guard isExpired(creds) else { return creds.token.accessToken }

        let refreshed = try await auth.refresh(token: creds.token, credentials: creds.deviceCredentials)
        let updated = StoredCredentials(token: refreshed,
                                        deviceCredentials: creds.deviceCredentials,
                                        obtainedAt: now())
        try store.save(updated)
        cached = updated
        return refreshed.accessToken
    }

    public func signOut() throws {
        try store.clear()
        cached = nil
    }

    private func currentCredentials() throws -> StoredCredentials? {
        if let cached { return cached }
        cached = try store.load()
        return cached
    }

    private func isExpired(_ creds: StoredCredentials) -> Bool {
        let expiry = creds.obtainedAt.addingTimeInterval(TimeInterval(creds.token.expiresIn) - refreshSkew)
        return now() >= expiry
    }
}
