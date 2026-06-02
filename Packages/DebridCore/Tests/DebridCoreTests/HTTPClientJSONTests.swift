import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct HTTPClientJSONTests {
        init() { MockURLProtocol.handler = nil }

        struct Echo: Codable, Equatable { let value: String }

        @Test func postJSONDecodesTheResponse() async throws {
            MockURLProtocol.stub(status: 200, json: #"{"value":"ok"}"#)
            let client = HTTPClient(session: .mock)
            let out: Echo = try await client.post(URL(string: "https://x/login")!, json: Echo(value: "hi"))
            #expect(out == Echo(value: "ok"))
        }

        @Test func dataReturnsRawBytes() async throws {
            MockURLProtocol.stub(status: 200, json: "SUBTITLE-BYTES")
            let client = HTTPClient(session: .mock)
            let bytes = try await client.data(URL(string: "https://x/file.srt")!)
            #expect(String(decoding: bytes, as: UTF8.self) == "SUBTITLE-BYTES")
        }

        @Test func dataThrowsOnNon2xx() async throws {
            MockURLProtocol.stub(status: 404, json: "nope")
            let client = HTTPClient(session: .mock)
            await #expect(throws: HTTPError.self) {
                _ = try await client.data(URL(string: "https://x/missing")!)
            }
        }
    }
}
