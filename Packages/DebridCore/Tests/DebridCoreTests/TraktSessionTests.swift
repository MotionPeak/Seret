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

    @Test func throwsWhenNotSignedIn() async throws {
        let session = TraktSession(store: MemoryStore(),
                                   refresh: { $0 }, now: { Date() })
        await #expect(throws: TraktSessionError.notSignedIn) { _ = try await session.validAccessToken() }
    }
}
