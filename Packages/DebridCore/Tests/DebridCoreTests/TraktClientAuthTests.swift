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
    }
}
