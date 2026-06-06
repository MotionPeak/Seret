import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct HTTPClientPostFormTests {
        init() { MockURLProtocol.handler = nil }

        @Test func postFormSucceedsOnEmpty204Body() async throws {
            MockURLProtocol.handler = { request in
                let body = request.bodyString()
                #expect(body.contains("files=all"))
                let response = HTTPURLResponse(url: request.url!, statusCode: 204,
                                               httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            let client = HTTPClient(session: .mock)
            // Should NOT throw despite the empty body.
            try await client.postForm(URL(string: "https://example.com/x")!, form: ["files": "all"])
        }

        @Test func postFormThrowsOnErrorStatus() async throws {
            MockURLProtocol.stub(status: 400, json: #"{"error":"bad"}"#)
            let client = HTTPClient(session: .mock)
            await #expect(throws: HTTPError.self) {
                try await client.postForm(URL(string: "https://example.com/x")!, form: [:])
            }
        }
    }
}

/// Test helper: read a URLRequest's httpBody (or httpBodyStream) as a String.
extension URLRequest {
    func bodyString() -> String {
        if let body = httpBody { return String(decoding: body, as: UTF8.self) }
        guard let stream = httpBodyStream else { return "" }
        stream.open(); defer { stream.close() }
        var data = Data(); let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
