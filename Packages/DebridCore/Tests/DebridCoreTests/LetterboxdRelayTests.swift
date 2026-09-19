import Testing
import Foundation
@testable import DebridCore

/// Captures the one request under test. A class because the mock handler is a `@Sendable` closure.
private final class SentRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?
    private var body: Data?

    /// The body is read here, not lazily: `URLProtocol` hands it back as a stream, and the stream
    /// is only readable while the request is in flight.
    func record(_ r: URLRequest) {
        let captured = r.httpBody ?? r.httpBodyStream.map(Self.drain)
        lock.withLock {
            request = r
            body = captured
        }
    }

    var path: String? { lock.withLock { request?.url?.path } }
    var method: String? { lock.withLock { request?.httpMethod } }
    var jsonBody: [String: Any]? {
        lock.withLock {
            guard let body else { return nil }
            return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        }
    }

    private static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

extension MockTests {
    @Suite struct LetterboxdRelayTests {
        init() { MockURLProtocol.handler = nil }

        private func relay() -> HTTPLetterboxdRelay {
            HTTPLetterboxdRelay(http: HTTPClient(session: .mock),
                                baseURL: URL(string: "http://nas.local:8080")!)
        }

        private func respond(_ status: Int) {
            MockURLProtocol.handler = { request in
                (HTTPURLResponse(url: request.url!, statusCode: status,
                                 httpVersion: nil, headerFields: nil)!, Data())
            }
        }

        @Test func postsTheWriteToTheDiaryEndpoint() async throws {
            let seen = SentRequest()
            MockURLProtocol.handler = { request in
                seen.record(request)
                return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                        httpVersion: nil, headerFields: nil)!, Data())
            }
            try await relay().send(LetterboxdWrite(tmdbID: 73, rating: 9,
                                                   watchedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                   rewatch: true))
            #expect(seen.path == "/api/letterboxd/diary")
            #expect(seen.method == "POST")
            let body = try #require(seen.jsonBody)
            #expect(body["tmdbID"] as? Int == 73)
            #expect(body["rating"] as? Int == 9)
            #expect(body["rewatch"] as? Bool == true)
        }

        /// Vapor decodes dates as ISO-8601. `JSONEncoder`'s default writes seconds since 2001, and
        /// the mismatch does not fail — it files the diary entry in the wrong year.
        @Test func theWatchDateIsISO8601() async throws {
            let seen = SentRequest()
            MockURLProtocol.handler = { request in
                seen.record(request)
                return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                        httpVersion: nil, headerFields: nil)!, Data())
            }
            try await relay().send(LetterboxdWrite(tmdbID: 73, rating: nil,
                                                   watchedAt: Date(timeIntervalSince1970: 1_700_000_000)))
            let body = try #require(seen.jsonBody)
            #expect(body["watchedAt"] as? String == "2023-11-14T22:13:20Z")
        }

        /// The server distinguishes three failures on purpose. Flattening them here would throw
        /// that away at the last step and leave the queue retrying something that cannot succeed.
        @Test func aSignedOutBrowserIsNotAuthenticated() async {
            respond(401)
            await #expect(throws: LetterboxdError.notAuthenticated) {
                try await self.relay().send(LetterboxdWrite(tmdbID: 73, rating: nil))
            }
        }

        @Test func aChallengeIsAChallenge() async {
            respond(503)
            await #expect(throws: LetterboxdError.challenged) {
                try await self.relay().send(LetterboxdWrite(tmdbID: 73, rating: nil))
            }
        }

        @Test func anUnknownFilmIsFilmNotFound() async {
            respond(404)
            await #expect(throws: LetterboxdError.filmNotFound) {
                try await self.relay().send(LetterboxdWrite(tmdbID: 73, rating: nil))
            }
        }

        /// The Synology being off is the ordinary case, not an error worth giving up on.
        @Test func anUnreachableServerIsTransient() async {
            MockURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
            do {
                try await relay().send(LetterboxdWrite(tmdbID: 73, rating: nil))
                Issue.record("expected a throw")
            } catch let error as LetterboxdError {
                guard case .transient = error else {
                    Issue.record("expected .transient, got \(error)")
                    return
                }
            } catch {
                Issue.record("expected a LetterboxdError, got \(error)")
            }
        }
    }
}
