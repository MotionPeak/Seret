import Testing
import Foundation
@testable import DebridCore

struct OMDbRatingsValueTests {
    @Test func hasAnyTrueWithAnyScore() {
        #expect(OMDbRatings(imdb: 8.7, rottenTomatoes: nil, metacritic: nil).hasAny)
        #expect(OMDbRatings(imdb: nil, rottenTomatoes: 88, metacritic: nil).hasAny)
        #expect(OMDbRatings(imdb: nil, rottenTomatoes: nil, metacritic: 73).hasAny)
    }

    @Test func hasAnyFalseWhenAllNil() {
        #expect(!OMDbRatings(imdb: nil, rottenTomatoes: nil, metacritic: nil).hasAny)
    }
}

extension MockTests {
    @Suite struct OMDbClientTests {
        init() { MockURLProtocol.handler = nil }

        func client() -> OMDbClient { OMDbClient(apiKey: "KEY", http: HTTPClient(session: .mock)) }

        @Test func parsesAllThreeRatings() async throws {
            MockURLProtocol.stub(status: 200, json: """
            {"Title":"The Matrix","imdbRating":"8.7","Metascore":"73",
             "Ratings":[{"Source":"Internet Movie Database","Value":"8.7/10"},
                        {"Source":"Rotten Tomatoes","Value":"88%"},
                        {"Source":"Metacritic","Value":"73/100"}],
             "Response":"True"}
            """)
            let r = try await client().ratings(imdbID: "tt0133093")
            #expect(r.imdb == 8.7)
            #expect(r.rottenTomatoes == 88)
            #expect(r.metacritic == 73)
        }

        @Test func sendsApiKeyAndImdbID() async throws {
            MockURLProtocol.handler = { request in
                let url = request.url!.absoluteString
                #expect(url.contains("omdbapi.com"))
                #expect(url.contains("apikey=KEY"))
                #expect(url.contains("i=tt0133093"))
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(#"{"Response":"True","imdbRating":"8.7"}"#.utf8))
            }
            _ = try await client().ratings(imdbID: "tt0133093")
        }

        @Test func missingRottenTomatoesIsNil() async throws {
            MockURLProtocol.stub(status: 200, json: """
            {"imdbRating":"7.2","Metascore":"N/A",
             "Ratings":[{"Source":"Internet Movie Database","Value":"7.2/10"}],
             "Response":"True"}
            """)
            let r = try await client().ratings(imdbID: "tt1")
            #expect(r.imdb == 7.2)
            #expect(r.rottenTomatoes == nil)
            #expect(r.metacritic == nil)
        }

        @Test func allRatingsMissing() async throws {
            MockURLProtocol.stub(status: 200, json: #"{"imdbRating":"N/A","Metascore":"N/A","Response":"True"}"#)
            let r = try await client().ratings(imdbID: "tt2")
            #expect(!r.hasAny)
        }

        @Test func responseFalseThrowsNotFound() async throws {
            MockURLProtocol.stub(status: 200, json: #"{"Response":"False","Error":"Incorrect IMDb ID."}"#)
            await #expect(throws: OMDbError.notFound("Incorrect IMDb ID.")) {
                _ = try await client().ratings(imdbID: "bad")
            }
        }

        @Test func tvSeriesResponseParses() async throws {
            MockURLProtocol.stub(status: 200, json: """
            {"Title":"Breaking Bad","Type":"series","imdbRating":"9.5","Metascore":"N/A",
             "Ratings":[{"Source":"Internet Movie Database","Value":"9.5/10"}],
             "Response":"True"}
            """)
            let r = try await client().ratings(imdbID: "tt0903747")
            #expect(r.imdb == 9.5)
        }
    }
}
