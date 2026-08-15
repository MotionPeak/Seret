import Foundation

public enum TraktSessionError: Error, Equatable, Sendable { case notSignedIn }

/// Holds the Trakt token and refreshes it transparently. Mirrors RealDebridSession's coalescing.
public actor TraktSession {
    private let store: TraktTokenStoring
    private let refreshFn: @Sendable (TraktToken) async throws -> TraktToken
    private let now: @Sendable () -> Date
    private let skew: TimeInterval
    private var refreshTask: Task<TraktToken, Error>?
    /// A refresh that failed for a reason retrying cannot fix — Trakt does not recognise this
    /// build's client id, or the refresh token itself is dead. Latched so the doomed POST is fired
    /// ONCE rather than on every authed call: the scrobbler alone reaches this on start, on pause,
    /// on every heartbeat and on stop, so a permanently-rejected token hung a full failed
    /// round-trip off each of them. Cleared when a new token is established.
    private var permanentFailure: (any Error)?

    public init(store: TraktTokenStoring,
                refresh: @escaping @Sendable (TraktToken) async throws -> TraktToken,
                now: @escaping @Sendable () -> Date = { Date() },
                skew: TimeInterval = 60) {
        self.store = store
        self.refreshFn = refresh
        self.now = now
        self.skew = skew
    }

    public func establish(_ token: TraktToken) throws {
        permanentFailure = nil          // a fresh link deserves a fresh verdict
        try store.save(token)
    }
    public func signOut() throws {
        permanentFailure = nil
        try store.clear()
    }

    public func validAccessToken() async throws -> String {
        if let permanentFailure { throw permanentFailure }
        guard let token = try store.load() else { throw TraktSessionError.notSignedIn }
        if !isExpired(token) { return token.accessToken }
        return try await refreshed(token).accessToken
    }

    private func isExpired(_ t: TraktToken) -> Bool {
        let expiry = Date(timeIntervalSince1970: TimeInterval(t.createdAt + t.expiresIn))
        return now().addingTimeInterval(skew) >= expiry
    }

    private func refreshed(_ token: TraktToken) async throws -> TraktToken {
        if let task = refreshTask { return try await task.value }
        let task = Task<TraktToken, Error> {
            let new = try await refreshFn(token)
            try store.save(new)
            return new
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            return try await task.value
        } catch {
            if Self.isPermanent(error) { permanentFailure = error }
            throw error
        }
    }

    /// Whether a refresh failure is one that retrying can never fix. A dropped connection is not —
    /// latching on that would strand a perfectly good account the moment the Wi-Fi blinked.
    private static func isPermanent(_ error: Error) -> Bool {
        if error is TraktAuthError { return true }                       // .unknownClient
        guard case let .status(code, body)? = error as? HTTPError, code == 401 else { return false }
        return body.contains("invalid_grant") || body.contains("invalid_client")
    }
}

extension TraktSession {
    /// Token provider closure for `TraktClient(token:)`.
    public nonisolated func tokenProvider() -> @Sendable () async throws -> String {
        { try await self.validAccessToken() }
    }
}
