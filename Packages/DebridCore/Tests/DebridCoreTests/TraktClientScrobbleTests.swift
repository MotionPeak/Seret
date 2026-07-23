import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TraktClientScrobbleTests {
        init() { MockURLProtocol.handler = nil }

        @Test func scrobbleStartSendsIdentityAndProgress() async throws {
            let box = RequestBox()
            MockURLProtocol.handler = { req in
                box.request = req
                let body = #"{"action":"start","progress":42.5}"#
                return (HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!,
                        Data(body.utf8))
            }
            let client = TraktClient(clientID: "cid", clientSecret: "sec",
                                     http: HTTPClient(session: .mock), token: { "AT" })
            try await client.scrobble(.start, ref: .movie(tmdb: 27205), progress: 42.5)
            let sent = String(decoding: box.request?.httpBodyStreamData() ?? Data(), as: UTF8.self)
            #expect(sent.contains("\"tmdb\":27205"))
            #expect(sent.contains("\"progress\":42.5"))
            #expect(box.request?.value(forHTTPHeaderField: "Authorization") == "Bearer AT")
        }
    }
}

/// Captures a request across the URLProtocol boundary for assertions.
final class RequestBox: @unchecked Sendable {
    var request: URLRequest?
}

// URLProtocol strips httpBody into a stream; read it back for assertions.
extension URLRequest {
    func httpBodyStreamData() -> Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data(); let size = 4096; var buf = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buf, maxLength: size)
            if read > 0 { data.append(buf, count: read) } else { break }
        }
        return data
    }
}
