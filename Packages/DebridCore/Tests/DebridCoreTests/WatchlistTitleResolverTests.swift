import Testing
import Foundation
@testable import DebridCore

@Suite struct WatchlistNameTests {
    @Test func theTrailingYearIsStrippedForSearching() {
        #expect(WatchlistName.stripYear(from: "Speed (1994)") == "Speed")
        #expect(WatchlistName.stripYear(from: "The Lion King (2019)") == "The Lion King")
    }

    /// A year inside the title must survive; only a TRAILING parenthesised year goes.
    @Test func aYearInsideTheTitleIsKept() {
        #expect(WatchlistName.stripYear(from: "The Class of (1984) (1982)") == "The Class of (1984)")
        #expect(WatchlistName.stripYear(from: "1917 (2019)") == "1917")
    }

    @Test func aNameWithoutAYearIsUnchanged() {
        #expect(WatchlistName.stripYear(from: "Speed") == "Speed")
    }
}

extension MockTests {
    @Suite struct WatchlistTitleResolverTests {
        init() { MockURLProtocol.handler = nil }

        func resolver(json: String) -> TMDBWatchlistTitleResolver {
            MockURLProtocol.handler = { request in
                (HTTPURLResponse(url: request.url!, statusCode: 200,
                                 httpVersion: nil, headerFields: nil)!, Data(json.utf8))
            }
            return TMDBWatchlistTitleResolver(
                tmdb: TMDBClient(apiKey: "k", http: HTTPClient(session: .mock)))
        }

        @Test func takesTheFirstResult() async throws {
            let json = """
            {"results":[{"id":1637,"title":"Speed","release_date":"1994-06-10","poster_path":"/p.jpg"},
                        {"id":9,"title":"Speed 2","release_date":"1997-06-13","poster_path":null}]}
            """
            let match = try await resolver(json: json).match(name: "Speed (1994)", year: 1994)
            #expect(match == WatchlistMatch(tmdbID: 1637, posterPath: "/p.jpg"))
        }

        @Test func noResultsIsNilRatherThanAnError() async throws {
            let match = try await resolver(json: #"{"results":[]}"#)
                .match(name: "Nothing (1999)", year: 1999)
            #expect(match == nil)
        }

        @Test func aMissingPosterIsStillAMatch() async throws {
            let json = #"{"results":[{"id":5,"title":"X","release_date":"2000-01-01","poster_path":null}]}"#
            let match = try await resolver(json: json).match(name: "X (2000)", year: 2000)
            #expect(match?.tmdbID == 5)
            #expect(match?.posterPath == nil)
        }
    }
}
