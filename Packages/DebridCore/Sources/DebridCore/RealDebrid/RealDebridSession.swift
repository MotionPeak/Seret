import Foundation

public enum RealDebridSessionError: Error, Equatable {
    case notSignedIn
}

/// Owns the RD credential lifecycle: serves a valid access token, refreshing
/// transparently when the current one is within `refreshSkew` of expiry.
///
/// One `RealDebridSession` per active account. Concurrent refreshes are coalesced
/// into a single network call, so parallel callers never spend the one-time-use
/// refresh token twice. `cached` avoids a store read on the hot path; it is not
/// consistent across separate instances sharing a store.
public actor RealDebridSession {
    private let auth: RealDebridAuthClient
    private let store: TokenStore
    private let now: @Sendable () -> Date
    private let refreshSkew: TimeInterval

    private var cached: StoredCredentials?
    private var refreshTask: Task<StoredCredentials, Error>?

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

    /// Persist a personal API token (real-debrid.com/apitoken). Static: no refresh token,
    /// no device credentials — `validAccessToken()` returns it as-is and never refreshes.
    public func establishStaticToken(_ token: String) throws {
        let creds = StoredCredentials(
            token: RDToken(accessToken: token, refreshToken: "", expiresIn: 0, tokenType: "Bearer"),
            deviceCredentials: RDDeviceCredentials(clientID: "", clientSecret: ""),
            obtainedAt: now(),
            isStatic: true)
        try store.save(creds)
        cached = creds
    }

    public func validAccessToken() async throws -> String {
        guard let creds = try currentCredentials() else { throw RealDebridSessionError.notSignedIn }
        if creds.isStatic { return creds.token.accessToken }   // personal token: never refresh
        guard isExpired(creds) else { return creds.token.accessToken }
        let refreshed = try await refreshedCredentials(replacing: creds)
        return refreshed.token.accessToken
    }

    public func signOut() throws {
        try store.clear()
        cached = nil
    }

    /// Refreshes once even under concurrent callers: the first caller starts the
    /// network refresh and stores the `Task`; later callers await that same task.
    /// The nil-check and assignment below run without an `await`, so the actor
    /// guarantees only one task is ever created per expiry.
    private func refreshedCredentials(replacing creds: StoredCredentials) async throws -> StoredCredentials {
        if let refreshTask {
            return try await refreshTask.value
        }
        let auth = self.auth
        let now = self.now
        let store = self.store
        let task = Task<StoredCredentials, Error> {
            let refreshed = try await auth.refresh(token: creds.token, credentials: creds.deviceCredentials)
            let updated = StoredCredentials(token: refreshed,
                                            deviceCredentials: creds.deviceCredentials,
                                            obtainedAt: now())
            try store.save(updated)
            return updated
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let updated = try await task.value
            cached = updated
            return updated
        } catch HTTPError.status(let code, let body)
            where (400...403).contains(code) || body.contains("invalid_grant") {
            // The refresh token is definitively rejected (spent / rotated by another device /
            // revoked). RD's OAuth token endpoint returns this as HTTP 400 `invalid_grant` (per
            // OAuth2 RFC 6749 §5.2 — the same endpoint whose 400 the device-code poll already
            // treats as an OAuth grant state), NOT 401/403 — so match the 4xx grant-error range and
            // the `invalid_grant` marker. Clear the poisoned session so every later
            // validAccessToken() stops re-firing a doomed refresh (which would otherwise fail every
            // action AND hammer RD's token endpoint — itself a throttle risk); the next launch then
            // routes cleanly to sign-in. Transient/transport errors (network blip, 5xx) fall through
            // untouched, so a refresh stays retryable and a flaky connection never signs the user out.
            try? store.clear()
            cached = nil
            throw RealDebridSessionError.notSignedIn
        }
    }

    private func currentCredentials() throws -> StoredCredentials? {
        if let cached { return cached }
        cached = try store.load()
        return cached
    }

    private func isExpired(_ creds: StoredCredentials) -> Bool {
        // Refresh `refreshSkew` seconds early so a token never expires mid-request.
        // `>=` (not `>`) treats the exact expiry instant as already expired.
        let expiry = creds.obtainedAt.addingTimeInterval(TimeInterval(creds.token.expiresIn) - refreshSkew)
        return now() >= expiry
    }
}
