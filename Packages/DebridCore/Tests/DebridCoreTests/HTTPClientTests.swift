import Testing
import Foundation
@testable import DebridCore

@Suite(.serialized)
struct HTTPClientTests {
    struct Probe: Decodable, Equatable { let value: Int }

    @Test func getDecodesJSON() async throws {
        MockURLProtocol.stub(status: 200, json: #"{"value":42}"#)
        let client = HTTPClient(session: .mock)
        let out: Probe = try await client.get(URL(string: "https://example.com/x")!)
        #expect(out == Probe(value: 42))
    }

    @Test func nonSuccessStatusThrowsStatusError() async throws {
        MockURLProtocol.stub(status: 503, json: #"{"error":"down"}"#)
        let client = HTTPClient(session: .mock)
        await #expect(throws: HTTPError.self) {
            let _: Probe = try await client.get(URL(string: "https://example.com/x")!)
        }
    }

    @Test func postEncodesForm() async throws {
        let body = HTTPClient.encodeForm(["a": "1", "b": "x y"])
        #expect(body.contains("a=1"))
        #expect(body.contains("b=x%20y"))
    }
}
