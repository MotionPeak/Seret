import Testing
import Foundation
@testable import DebridCore

private final class MethodLog: @unchecked Sendable {
    private let lock = NSLock()
    private var methods: [String] = []

    func record(_ method: String) {
        lock.lock(); defer { lock.unlock() }
        methods.append(method)
    }

    var all: [String] {
        lock.lock(); defer { lock.unlock() }
        return methods
    }
}

extension MockTests {
    @Suite struct HTTPClientResolveTests {
        init() { MockURLProtocol.handler = nil }

        @Test func returnsTheFinalURLAfterARedirect() async throws {
            MockURLProtocol.handler = { request in
                #expect(request.httpMethod == "HEAD")
                let final = URL(string: "https://letterboxd.com/film/blade-runner-2049/")!
                return (HTTPURLResponse(url: final, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
            }
            let client = HTTPClient(session: URLSession.mock)
            let resolved = try await client.resolvedURL(for: URL(string: "https://letterboxd.com/tmdb/335984/")!)
            // URL.path drops the trailing slash, so assert the component the slug comes from.
            #expect(resolved.lastPathComponent == "blade-runner-2049")
        }

        @Test func fallsBackToGETWhenHEADIsRejected() async throws {
            let log = MethodLog()
            MockURLProtocol.handler = { request in
                log.record(request.httpMethod ?? "")
                let final = URL(string: "https://letterboxd.com/film/speed/")!
                if request.httpMethod == "HEAD" {
                    return (HTTPURLResponse(url: final, statusCode: 405, httpVersion: nil, headerFields: nil)!, Data())
                }
                return (HTTPURLResponse(url: final, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
            }
            let client = HTTPClient(session: URLSession.mock)
            let resolved = try await client.resolvedURL(for: URL(string: "https://letterboxd.com/tmdb/1637/")!)
            #expect(log.all == ["HEAD", "GET"])
            #expect(resolved.lastPathComponent == "speed")
        }

        @Test func a404Throws() async {
            MockURLProtocol.handler = { request in
                (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
            let client = HTTPClient(session: URLSession.mock)
            await #expect(throws: (any Error).self) {
                _ = try await client.resolvedURL(for: URL(string: "https://letterboxd.com/tmdb/99999999/")!)
            }
        }
    }
}
