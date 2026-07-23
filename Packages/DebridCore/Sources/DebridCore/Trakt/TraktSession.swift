import Foundation

public enum TraktSessionError: Error, Equatable, Sendable { case notSignedIn }

/// Holds the Trakt token and refreshes it transparently. Mirrors RealDebridSession's coalescing.
public actor TraktSession {
    private let store: TraktTokenStoring
    private let refreshFn: @Sendable (TraktToken) async throws -> TraktToken
    private let now: @Sendable () -> Date
    private let skew: TimeInterval
    private var refreshTask: Task<TraktToken, Error>?

    public init(store: TraktTokenStoring,
                refresh: @escaping @Sendable (TraktToken) async throws -> TraktToken,
                now: @escaping @Sendable () -> Date = { Date() },
                skew: TimeInterval = 60) {
        self.store = store
        self.refreshFn = refresh
        self.now = now
        self.skew = skew
    }

    public func establish(_ token: TraktToken) throws { try store.save(token) }
    public func signOut() throws { try store.clear() }

    public func validAccessToken() async throws -> String {
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
        return try await task.value
    }
}

extension TraktSession {
    /// Token provider closure for `TraktClient(token:)`.
    public nonisolated func tokenProvider() -> @Sendable () async throws -> String {
        { try await self.validAccessToken() }
    }
}
