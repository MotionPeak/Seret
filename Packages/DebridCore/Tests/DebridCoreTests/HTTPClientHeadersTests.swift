import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct HTTPClientHeadersTests {
        init() { MockURLProtocol.handler = nil }

        struct Body: Decodable, Equatable { let ok: Bool }

        @Test func getWithHeadersReturnsValueAndResponseHeaders() async throws {
            MockURLProtocol.handler = { request in
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["X-Pagination-Page-Count": "7"])!
                return (response, Data(#"{"ok":true}"#.utf8))
            }
            let client = HTTPClient(session: .mock)
            let (value, response): (Body, HTTPURLResponse) =
                try await client.getWithHeaders(URL(string: "https://example.com/x")!)
            #expect(value == Body(ok: true))
            #expect(response.value(forHTTPHeaderField: "X-Pagination-Page-Count") == "7")
        }
    }
}
