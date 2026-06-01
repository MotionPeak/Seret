import Testing
import Foundation
@testable import DebridCore

// NOTE: RealDebridAuthClientTests is nested inside MockTests (see MockTests.swift)
// to ensure global serialization with all other suites that share MockURLProtocol.
extension MockTests {
    @Suite struct RealDebridAuthClientTests {
        init() { MockURLProtocol.handler = nil }

        @Test func startDeviceCodeDecodes() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"device_code":"DC","user_code":"LF2NKTKX","interval":5,
             "expires_in":1800,"verification_url":"https://real-debrid.com/device"}
            """#)
            let client = RealDebridAuthClient(http: HTTPClient(session: .mock))
            let code = try await client.startDeviceCode()
            #expect(code.userCode == "LF2NKTKX")
            #expect(code.interval == 5)
            #expect(code.verificationURL == "https://real-debrid.com/device")
            #expect(code.deviceCode == "DC")
            #expect(code.expiresIn == 1800)
        }

        @Test func pollCredentialsReturnsNilWhilePending() async throws {
            MockURLProtocol.stub(status: 400, json: #"{"error":"authorization_pending"}"#)
            let client = RealDebridAuthClient(http: HTTPClient(session: .mock))
            let creds = try await client.pollCredentials(deviceCode: "DC")
            #expect(creds == nil)
        }

        @Test func pollCredentialsReturnsCredentialsWhenAuthorized() async throws {
            MockURLProtocol.stub(status: 200, json: #"{"client_id":"CID","client_secret":"CSECRET"}"#)
            let client = RealDebridAuthClient(http: HTTPClient(session: .mock))
            let creds = try await client.pollCredentials(deviceCode: "DC")
            #expect(creds?.clientID == "CID")
            #expect(creds?.clientSecret == "CSECRET")
        }

        @Test func requestTokenDecodes() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"access_token":"AT","expires_in":3600,"token_type":"Bearer","refresh_token":"RT"}
            """#)
            let client = RealDebridAuthClient(http: HTTPClient(session: .mock))
            let token = try await client.requestToken(
                deviceCode: "DC",
                credentials: .init(clientID: "CID", clientSecret: "CSECRET"))
            #expect(token.accessToken == "AT")
            #expect(token.refreshToken == "RT")
            #expect(token.expiresIn == 3600)
        }

        @Test func pollCredentialsThrowsWhenNotPending() async throws {
            MockURLProtocol.stub(status: 403, json: #"{"error":"access_denied"}"#)
            let client = RealDebridAuthClient(http: HTTPClient(session: .mock))
            await #expect(throws: HTTPError.self) {
                _ = try await client.pollCredentials(deviceCode: "DC")
            }
        }

        @Test func refreshDecodes() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"access_token":"AT2","expires_in":3600,"token_type":"Bearer","refresh_token":"RT2"}
            """#)
            let client = RealDebridAuthClient(http: HTTPClient(session: .mock))
            let token = try await client.refresh(
                token: RDToken(accessToken: "AT", refreshToken: "RT", expiresIn: 3600, tokenType: "Bearer"),
                credentials: .init(clientID: "CID", clientSecret: "CSECRET"))
            #expect(token.accessToken == "AT2")
            #expect(token.refreshToken == "RT2")
        }
    }
}
