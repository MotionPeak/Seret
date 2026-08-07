import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TraktClientAuthTests {
        init() { MockURLProtocol.handler = nil }

        @Test func startDeviceCodeDecodes() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"device_code":"DC","user_code":"AB12","verification_url":"https://trakt.tv/activate",
             "expires_in":600,"interval":5}
            """#)
            let client = TraktClient(clientID: "cid", clientSecret: "sec", http: HTTPClient(session: .mock))
            let code = try await client.startDeviceCode()
            #expect(code.userCode == "AB12")
        }

        @Test func pollPendingReturnsNil() async throws {
            MockURLProtocol.stub(status: 400, json: #"{"error":"authorization_pending"}"#)
            let client = TraktClient(clientID: "cid", clientSecret: "sec", http: HTTPClient(session: .mock))
            let token = try await client.pollToken(deviceCode: "DC")
            #expect(token == nil)
        }

        @Test func pollSuccessReturnsToken() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"access_token":"AT","refresh_token":"RT","expires_in":7776000,
             "created_at":1700000000,"token_type":"bearer","scope":"public"}
            """#)
            let client = TraktClient(clientID: "cid", clientSecret: "sec", http: HTTPClient(session: .mock))
            let token = try await client.pollToken(deviceCode: "DC")
            #expect(token?.accessToken == "AT")
        }

        @Test func expiredCodeThrows() async throws {
            MockURLProtocol.stub(status: 410, json: #"{"error":"expired"}"#)
            let client = TraktClient(clientID: "cid", clientSecret: "sec", http: HTTPClient(session: .mock))
            await #expect(throws: TraktAuthError.deviceCodeExpired) {
                _ = try await client.pollToken(deviceCode: "DC")
            }
        }

        // MARK: Trakt no longer recognising this app's credentials
        //
        // The failure that went undiagnosed for days: Trakt deleted the API app, so every OAuth
        // call answers 401 invalid_client. Nothing mapped that, so it surfaced as the generic
        // "check your connection" — which is a lie, and sent the diagnosis down the wrong path.

        @Test func deviceCodeWithAnUnknownClientIDSaysSo() async throws {
            MockURLProtocol.stub(status: 401,
                                 json: #"{"error":"invalid_client","error_description":"client not found"}"#)
            let client = TraktClient(clientID: "cid", clientSecret: "sec", http: HTTPClient(session: .mock))
            await #expect(throws: TraktAuthError.unknownClient) {
                _ = try await client.startDeviceCode()
            }
        }

        @Test func pollWithAnUnknownClientIDSaysSo() async throws {
            MockURLProtocol.stub(status: 401,
                                 json: #"{"error":"invalid_client","error_description":"client not found"}"#)
            let client = TraktClient(clientID: "cid", clientSecret: "sec", http: HTTPClient(session: .mock))
            await #expect(throws: TraktAuthError.unknownClient) {
                _ = try await client.pollToken(deviceCode: "DC")
            }
        }

        @Test func refreshWithAnUnknownClientIDSaysSo() async throws {
            MockURLProtocol.stub(status: 401,
                                 json: #"{"error":"invalid_client","error_description":"client not found"}"#)
            let client = TraktClient(clientID: "cid", clientSecret: "sec", http: HTTPClient(session: .mock))
            let stale = TraktToken(accessToken: "AT", refreshToken: "RT", expiresIn: 1,
                                   createdAt: 0, tokenType: "bearer", scope: "public")
            await #expect(throws: TraktAuthError.unknownClient) {
                _ = try await client.refresh(stale)
            }
        }

        /// A dead REFRESH TOKEN is a different problem with a different remedy (relink), so it must
        /// NOT be reported as dead app credentials. Same status, different body — the body decides.
        @Test func aRejectedRefreshTokenIsNotReportedAsAnUnknownClient() async throws {
            MockURLProtocol.stub(status: 401,
                                 json: #"{"error":"invalid_grant","error_description":"token revoked"}"#)
            let client = TraktClient(clientID: "cid", clientSecret: "sec", http: HTTPClient(session: .mock))
            let stale = TraktToken(accessToken: "AT", refreshToken: "RT", expiresIn: 1,
                                   createdAt: 0, tokenType: "bearer", scope: "public")
            await #expect(throws: HTTPError.status(code: 401, body: #"{"error":"invalid_grant","error_description":"token revoked"}"#)) {
                _ = try await client.refresh(stale)
            }
        }

        /// `pollToken` used to rethrow with `body: ""`, throwing away the one field that says WHY.
        @Test func anUnexpectedPollStatusKeepsItsBody() async throws {
            MockURLProtocol.stub(status: 503, json: #"{"error":"maintenance"}"#)
            let client = TraktClient(clientID: "cid", clientSecret: "sec", http: HTTPClient(session: .mock))
            await #expect(throws: HTTPError.status(code: 503, body: #"{"error":"maintenance"}"#)) {
                _ = try await client.pollToken(deviceCode: "DC")
            }
        }
    }
}
