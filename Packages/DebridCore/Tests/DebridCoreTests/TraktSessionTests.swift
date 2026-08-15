import Testing
import Foundation
@testable import DebridCore

@Suite struct TraktSessionTests {
    final class MemoryStore: TraktTokenStoring, @unchecked Sendable {
        var token: TraktToken?
        func load() throws -> TraktToken? { token }
        func save(_ t: TraktToken) throws { token = t }
        func clear() throws { token = nil }
    }

    func token(created: Int, expires: Int, access: String = "AT", refresh: String = "RT") -> TraktToken {
        .init(accessToken: access, refreshToken: refresh, expiresIn: expires,
              createdAt: created, tokenType: "bearer", scope: "public")
    }

    @Test func returnsStoredTokenWhenFresh() async throws {
        let store = MemoryStore()
        try store.save(token(created: 1_000, expires: 7_776_000))
        let session = TraktSession(store: store,
                                   refresh: { _ in Issue.record("should not refresh"); return self.token(created: 0, expires: 0) },
                                   now: { Date(timeIntervalSince1970: 2_000) })
        #expect(try await session.validAccessToken() == "AT")
    }

    @Test func refreshesWhenExpired() async throws {
        let store = MemoryStore()
        try store.save(token(created: 1_000, expires: 100))   // expires at 1_100
        let session = TraktSession(store: store,
                                   refresh: { _ in self.token(created: 5_000, expires: 7_776_000, access: "NEW") },
                                   now: { Date(timeIntervalSince1970: 2_000) })
        #expect(try await session.validAccessToken() == "NEW")
        #expect(try store.load()?.accessToken == "NEW")
    }

    /// Trakt not recognising this build's client id is not something retrying fixes, and every
    /// authed call went through here — the scrobbler alone reaches it on start, on pause, on every
    /// heartbeat and on stop. Without a latch each of those paid for a full doomed round-trip.
    @Test func aPermanentlyRejectedTokenIsOnlyRetriedOnce() async throws {
        let store = MemoryStore()
        try store.save(token(created: 1_000, expires: 100))       // expired → forces a refresh
        let attempts = Counter()
        let session = TraktSession(store: store,
                                   refresh: { _ in
                                       await attempts.bump()
                                       throw TraktAuthError.unknownClient
                                   },
                                   now: { Date(timeIntervalSince1970: 2_000) })

        for _ in 0..<5 { _ = try? await session.validAccessToken() }

        #expect(await attempts.count == 1)
    }

    /// …but a dropped connection is not permanent. Latching on that would unlink a perfectly good
    /// account the moment the Wi-Fi blinked.
    @Test func aTransientRefreshFailureKeepsBeingRetried() async throws {
        let store = MemoryStore()
        try store.save(token(created: 1_000, expires: 100))
        let attempts = Counter()
        let session = TraktSession(store: store,
                                   refresh: { _ in
                                       await attempts.bump()
                                       throw HTTPError.transport("offline")
                                   },
                                   now: { Date(timeIntervalSince1970: 2_000) })

        for _ in 0..<3 { _ = try? await session.validAccessToken() }

        #expect(await attempts.count == 3)
    }

    actor Counter {
        private(set) var count = 0
        func bump() { count += 1 }
    }

    @Test func throwsWhenNotSignedIn() async throws {
        let session = TraktSession(store: MemoryStore(),
                                   refresh: { $0 }, now: { Date() })
        await #expect(throws: TraktSessionError.notSignedIn) { _ = try await session.validAccessToken() }
    }
}
