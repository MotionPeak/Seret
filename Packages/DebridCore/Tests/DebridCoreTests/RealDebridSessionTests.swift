import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct RealDebridSessionTests {
        init() { MockURLProtocol.handler = nil }

        private func creds(expiresIn: Int, obtainedAt: Date) -> StoredCredentials {
            StoredCredentials(
                token: RDToken(accessToken: "AT-OLD", refreshToken: "RT", expiresIn: expiresIn, tokenType: "Bearer"),
                deviceCredentials: RDDeviceCredentials(clientID: "CID", clientSecret: "CSECRET"),
                obtainedAt: obtainedAt)
        }

        @Test func returnsNotSignedInWhenEmpty() async throws {
            let session = RealDebridSession(
                auth: RealDebridAuthClient(http: HTTPClient(session: .mock)),
                store: InMemoryTokenStore())
            await #expect(throws: RealDebridSessionError.notSignedIn) {
                _ = try await session.validAccessToken()
            }
        }

        @Test func returnsCachedTokenWhenStillValid() async throws {
            let store = InMemoryTokenStore()
            let t0 = Date(timeIntervalSince1970: 1_000_000)
            try store.save(creds(expiresIn: 3600, obtainedAt: t0))
            let session = RealDebridSession(
                auth: RealDebridAuthClient(http: HTTPClient(session: .mock)),
                store: store,
                now: { t0.addingTimeInterval(60) })  // only 1 min elapsed
            let token = try await session.validAccessToken()
            #expect(token == "AT-OLD")
        }

        @Test func refreshesWhenExpired() async throws {
            let store = InMemoryTokenStore()
            let t0 = Date(timeIntervalSince1970: 1_000_000)
            try store.save(creds(expiresIn: 3600, obtainedAt: t0))
            MockURLProtocol.stub(status: 200, json: #"""
            {"access_token":"AT-NEW","expires_in":3600,"token_type":"Bearer","refresh_token":"RT2"}
            """#)
            let session = RealDebridSession(
                auth: RealDebridAuthClient(http: HTTPClient(session: .mock)),
                store: store,
                now: { t0.addingTimeInterval(3600) })  // fully elapsed → expired
            let token = try await session.validAccessToken()
            #expect(token == "AT-NEW")
            #expect(try store.load()?.token.refreshToken == "RT2")  // persisted
        }

        @Test func refreshesExactlyAtSkewBoundary() async throws {
            let store = InMemoryTokenStore()
            let t0 = Date(timeIntervalSince1970: 1_000_000)
            try store.save(creds(expiresIn: 3600, obtainedAt: t0))  // expiry = t0 + 3540 (skew 60)
            MockURLProtocol.stub(status: 200, json: #"""
            {"access_token":"AT-NEW","expires_in":3600,"token_type":"Bearer","refresh_token":"RT2"}
            """#)
            let session = RealDebridSession(
                auth: RealDebridAuthClient(http: HTTPClient(session: .mock)),
                store: store,
                now: { t0.addingTimeInterval(3540) })  // exactly at the expiry instant
            let token = try await session.validAccessToken()
            #expect(token == "AT-NEW")
        }

        @Test func refreshFailureLeavesStoredCredentialsIntact() async throws {
            let store = InMemoryTokenStore()
            let t0 = Date(timeIntervalSince1970: 1_000_000)
            try store.save(creds(expiresIn: 3600, obtainedAt: t0))
            MockURLProtocol.stub(status: 401, json: #"{"error":"invalid_grant"}"#)
            let session = RealDebridSession(
                auth: RealDebridAuthClient(http: HTTPClient(session: .mock)),
                store: store,
                now: { t0.addingTimeInterval(3600) })  // expired
            await #expect(throws: HTTPError.self) {
                _ = try await session.validAccessToken()
            }
            #expect(try store.load()?.token.refreshToken == "RT")  // unchanged after failed refresh
        }
    }
}
