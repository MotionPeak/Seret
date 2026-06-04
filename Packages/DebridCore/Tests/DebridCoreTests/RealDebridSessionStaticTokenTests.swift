import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct RealDebridSessionStaticTokenTests {
        init() { MockURLProtocol.handler = nil }

        @Test func staticTokenReturnedWithoutRefresh() async throws {
            // A refresh stub is armed; if validAccessToken refreshed, it would return AT-REFRESHED.
            MockURLProtocol.stub(status: 200, json: #"""
            {"access_token":"AT-REFRESHED","expires_in":3600,"token_type":"Bearer","refresh_token":"RT2"}
            """#)
            let store = InMemoryTokenStore()
            let session = RealDebridSession(
                auth: RealDebridAuthClient(http: HTTPClient(session: .mock)),
                store: store,
                now: { Date(timeIntervalSince1970: 1_000_000) })

            try await session.establishStaticToken("STATIC-TOK")
            let token = try await session.validAccessToken()

            #expect(token == "STATIC-TOK")           // not AT-REFRESHED → no refresh occurred
            #expect(try store.load()?.isStatic == true)
            #expect(try store.load()?.token.accessToken == "STATIC-TOK")
        }
    }
}
