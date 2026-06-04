import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct RealDebridValidateTokenTests {
        init() { MockURLProtocol.handler = nil }

        @Test func trueWhenUserEndpointReturns200() async throws {
            MockURLProtocol.stub(status: 200, json: #"{"id":123,"username":"neo"}"#)
            let client = RealDebridAuthClient(http: HTTPClient(session: .mock))
            #expect(try await client.validateToken("TOK") == true)
        }

        @Test func falseWhenUnauthorized() async throws {
            MockURLProtocol.stub(status: 401, json: #"{"error":"bad_token"}"#)
            let client = RealDebridAuthClient(http: HTTPClient(session: .mock))
            #expect(try await client.validateToken("TOK") == false)
        }

        @Test func rethrowsOnServerError() async {
            MockURLProtocol.stub(status: 500, json: #"{"error":"server"}"#)
            let client = RealDebridAuthClient(http: HTTPClient(session: .mock))
            await #expect(throws: (any Error).self) {
                _ = try await client.validateToken("TOK")
            }
        }
    }
}
