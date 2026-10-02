import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    /// TheIntroDB: crowdsourced intro/credits timestamps keyed by TMDB id. Public, no key.
    @Suite struct TheIntroDBClientTests {
        init() { MockURLProtocol.handler = nil }

        func client() -> TheIntroDBClient { TheIntroDBClient(http: HTTPClient(session: .mock)) }

        /// Fight Club, as the live API answers it.
        @Test func readsWhereTheCreditsStartInSeconds() async throws {
            MockURLProtocol.stub(status: 200, json: """
            {"tmdb_id":550,"type":"movie","intro":[{"start_ms":null,"end_ms":119000}],
             "credits":[{"start_ms":8177000,"end_ms":8348000}]}
            """)
            let start = try await client().creditsStart(tmdbID: 550, durationSeconds: 8340)
            #expect(start == 8177)
        }

        @Test func asksForTheFilmByTMDBIDWithItsRuntime() async throws {
            MockURLProtocol.handler = { request in
                let url = request.url!.absoluteString
                #expect(url.hasPrefix("https://api.theintrodb.org/v3/media?"))
                #expect(url.contains("tmdb_id=550"))
                #expect(url.contains("duration_ms=8340000"))
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(#"{"tmdb_id":550,"type":"movie"}"#.utf8))
            }
            _ = try await client().creditsStart(tmdbID: 550, durationSeconds: 8340)
        }

        /// A mid-credits scene splits the roll in two; the film is over at the FIRST.
        @Test func theEarliestCreditsSegmentIsWhereTheFilmEnds() async throws {
            MockURLProtocol.stub(status: 200, json: """
            {"tmdb_id":1,"type":"movie","credits":[{"start_ms":7600000,"end_ms":null},
                                                   {"start_ms":7300000,"end_ms":7500000}]}
            """)
            #expect(try await client().creditsStart(tmdbID: 1, durationSeconds: 7700) == 7300)
        }

        /// `start_ms: null` means "from the first frame" — never the credits of a film.
        @Test func aCreditsSegmentWithNoStartIsIgnored() async throws {
            MockURLProtocol.stub(status: 200, json: """
            {"tmdb_id":1,"type":"movie","credits":[{"start_ms":null,"end_ms":9000}]}
            """)
            #expect(try await client().creditsStart(tmdbID: 1, durationSeconds: 7700) == nil)
        }

        /// Inception: an intro is known, the credits are not.
        @Test func aFilmWithNoCreditsTimestampHasNone() async throws {
            MockURLProtocol.stub(status: 200, json: """
            {"tmdb_id":27205,"type":"movie","intro":[{"start_ms":null,"end_ms":38000}]}
            """)
            #expect(try await client().creditsStart(tmdbID: 27205, durationSeconds: 8880) == nil)
        }

        /// Most films are not in the database at all; that is an answer, not a failure.
        @Test func aFilmTheDatabaseDoesNotKnowHasNoCredits() async throws {
            MockURLProtocol.stub(status: 404, json: #"{"error":"media not found"}"#)
            #expect(try await client().creditsStart(tmdbID: 489, durationSeconds: 7560) == nil)
        }

        @Test func aServerErrorIsAFailure() async throws {
            MockURLProtocol.stub(status: 503, json: "{}")
            await #expect(throws: HTTPError.self) {
                _ = try await client().creditsStart(tmdbID: 489, durationSeconds: 7560)
            }
        }
    }
}
