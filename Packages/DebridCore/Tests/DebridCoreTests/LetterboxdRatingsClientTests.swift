import Testing
import Foundation
@testable import DebridCore

private struct StubResolver: LetterboxdFilmResolving {
    let slug: String?
    func slug(forTMDB id: Int) async throws -> String {
        guard let slug else { throw LetterboxdError.filmNotFound }
        return slug
    }
}

extension MockTests {
    @Suite struct LetterboxdRatingsClientTests {
        init() { MockURLProtocol.handler = nil }

        private func fixture(_ name: String) throws -> Data {
            let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures")!
            return try Data(contentsOf: url)
        }

        private func client(slug: String?) -> LetterboxdRatingsClient {
            LetterboxdRatingsClient(http: HTTPClient(session: .mock), resolver: StubResolver(slug: slug))
        }

        @Test func readsTheScoreFromTheResolvedFilmsPage() async throws {
            let page = try fixture("letterboxd-film-rated")
            MockURLProtocol.handler = { request in
                // The trailing slash is what Letterboxd serves without a redirect.
                #expect(request.url!.absoluteString == "https://letterboxd.com/film/dune-part-two/")
                return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                        httpVersion: nil, headerFields: nil)!, page)
            }
            let rating = try await client(slug: "dune-part-two").rating(forTMDB: 693134)
            #expect(rating == LetterboxdFilmRating(score: 4.38, count: 3_654_485))
        }

        /// A film with no score yet is an answer, not a failure — the caller caches it so an
        /// unreleased title stops costing a 47 KB page on every detail open.
        @Test func aFilmWithNoScoreYetIsNilRatherThanAnError() async throws {
            let page = try fixture("letterboxd-film-unrated")
            MockURLProtocol.handler = { request in
                (HTTPURLResponse(url: request.url!, statusCode: 200,
                                 httpVersion: nil, headerFields: nil)!, page)
            }
            #expect(try await client(slug: "avengers-doomsday").rating(forTMDB: 1) == nil)
        }

        /// Letterboxd indexes films only, so every TV show resolves to nothing. That must stay
        /// distinguishable from a refusal: one is permanent, the other is worth retrying.
        @Test func aTitleLetterboxdHasNoFilmForThrowsFilmNotFound() async {
            await #expect(throws: LetterboxdError.filmNotFound) {
                try await client(slug: nil).rating(forTMDB: 1396)
            }
        }

        /// Cloudflare refusing, or the network being down, says nothing about the film. It must not
        /// arrive as "no score", which would be cached and suppress a real rating.
        @Test func aRefusedRequestThrowsRatherThanReadingAsNoScore() async {
            MockURLProtocol.handler = { request in
                (HTTPURLResponse(url: request.url!, statusCode: 403,
                                 httpVersion: nil, headerFields: nil)!, Data())
            }
            await #expect(throws: (any Error).self) {
                try await client(slug: "dune-part-two").rating(forTMDB: 693134)
            }
        }
    }
}
