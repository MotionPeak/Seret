import Testing
import Foundation
@testable import DebridCore

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func bump() {
        lock.lock(); defer { lock.unlock() }
        value += 1
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

extension MockTests {
    @Suite struct LetterboxdFilmResolverTests {
        init() { MockURLProtocol.handler = nil }

        @Test func resolvesASlugFromTheRedirectDestination() async throws {
            MockURLProtocol.handler = { request in
                #expect(request.url!.path == "/tmdb/335984")
                let final = URL(string: "https://letterboxd.com/film/blade-runner-2049/")!
                return (HTTPURLResponse(url: final, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
            }
            let resolver = LetterboxdFilmResolver(http: HTTPClient(session: .mock), map: LetterboxdFilmMap())
            #expect(try await resolver.slug(forTMDB: 335984) == "blade-runner-2049")
        }

        @Test func aSecondLookupIsServedFromTheMapWithoutARequest() async throws {
            let counter = RequestCounter()
            MockURLProtocol.handler = { _ in
                counter.bump()
                let final = URL(string: "https://letterboxd.com/film/speed/")!
                return (HTTPURLResponse(url: final, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
            }
            let resolver = LetterboxdFilmResolver(http: HTTPClient(session: .mock), map: LetterboxdFilmMap())
            _ = try await resolver.slug(forTMDB: 1637)
            _ = try await resolver.slug(forTMDB: 1637)
            #expect(counter.count == 1)
        }

        @Test func anUnknownFilmIsFilmNotFound() async {
            MockURLProtocol.handler = { request in
                (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
            let resolver = LetterboxdFilmResolver(http: HTTPClient(session: .mock), map: LetterboxdFilmMap())
            await #expect(throws: LetterboxdError.filmNotFound) {
                _ = try await resolver.slug(forTMDB: 99999999)
            }
        }

        @Test func aDestinationThatIsNotAFilmPageIsFilmNotFound() async {
            MockURLProtocol.handler = { _ in
                // Letterboxd bounces an unknown id to the home page rather than 404ing.
                let final = URL(string: "https://letterboxd.com/")!
                return (HTTPURLResponse(url: final, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
            }
            let resolver = LetterboxdFilmResolver(http: HTTPClient(session: .mock), map: LetterboxdFilmMap())
            await #expect(throws: LetterboxdError.filmNotFound) {
                _ = try await resolver.slug(forTMDB: 4242)
            }
        }

        /// A blocked request is not a missing film. Cloudflare 403s some clients outright, and
        /// calling that `filmNotFound` tells the caller to give up on a film that is right there.
        @Test func aRefusedRequestIsTransientNotMissing() async {
            MockURLProtocol.handler = { request in
                (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!,
                 Data("Just a moment".utf8))
            }
            let resolver = LetterboxdFilmResolver(http: HTTPClient(session: .mock), map: LetterboxdFilmMap())
            await #expect(throws: LetterboxdError.self) {
                _ = try await resolver.slug(forTMDB: 73)
            }
            do {
                _ = try await resolver.slug(forTMDB: 73)
            } catch let error as LetterboxdError {
                guard case .transient(let message) = error else {
                    Issue.record("expected .transient, got \(error)")
                    return
                }
                #expect(message.contains("403"))
            } catch {
                Issue.record("expected a LetterboxdError, got \(error)")
            }
        }

        @Test func aSeededMapNeedsNoNetworkAtAll() async throws {
            MockURLProtocol.handler = { _ in
                Issue.record("resolver hit the network for a slug it had already been given")
                throw LetterboxdError.transient("unreachable")
            }
            let resolver = LetterboxdFilmResolver(http: HTTPClient(session: .mock),
                                                  map: LetterboxdFilmMap(seed: [550: "fight-club"]))
            #expect(try await resolver.slug(forTMDB: 550) == "fight-club")
        }
    }
}
