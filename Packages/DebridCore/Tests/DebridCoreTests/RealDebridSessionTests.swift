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

        @Test func refreshRejectionClearsSessionAndReportsNotSignedIn() async throws {
            // A definitive auth rejection — RD's OAuth token endpoint returns a spent/rotated/revoked
            // refresh token as HTTP 400 `invalid_grant` (OAuth2 RFC 6749 §5.2), NOT 401 — must clear
            // the poisoned session and report notSignedIn, so callers stop re-firing a doomed refresh
            // on every action and the next launch routes to sign-in.
            let store = InMemoryTokenStore()
            let t0 = Date(timeIntervalSince1970: 1_000_000)
            try store.save(creds(expiresIn: 3600, obtainedAt: t0))
            MockURLProtocol.stub(status: 400, json: #"{"error":"invalid_grant"}"#)
            let session = RealDebridSession(
                auth: RealDebridAuthClient(http: HTTPClient(session: .mock)),
                store: store,
                now: { t0.addingTimeInterval(3600) })  // expired
            await #expect(throws: RealDebridSessionError.notSignedIn) {
                _ = try await session.validAccessToken()
            }
            #expect(try store.load() == nil)   // poisoned creds purged — no doomed-refresh storm
        }

        @Test func transientRefreshFailureKeepsCredentialsForRetry() async throws {
            // A transient failure (5xx / network blip) must NOT sign the user out — the creds stay
            // so a later refresh can succeed when connectivity/RD recovers.
            let store = InMemoryTokenStore()
            let t0 = Date(timeIntervalSince1970: 1_000_000)
            try store.save(creds(expiresIn: 3600, obtainedAt: t0))
            MockURLProtocol.stub(status: 503, json: #"{"error":"temporarily_unavailable"}"#)
            let session = RealDebridSession(
                auth: RealDebridAuthClient(http: HTTPClient(session: .mock)),
                store: store,
                now: { t0.addingTimeInterval(3600) })  // expired
            await #expect(throws: HTTPError.self) {     // surfaced, not swallowed
                _ = try await session.validAccessToken()
            }
            #expect(try store.load()?.token.refreshToken == "RT")  // unchanged — still retryable
        }
    }
}
