import Testing
import Foundation
@testable import DebridCore

/// `vote_count` rides the movie details payload. The Watchlist's Highest Rated row needs it: a
/// film with a 9.4 from twelve voters is not "highly rated", it is unknown.
struct TMDBVoteCountTests {
    private func decode(_ json: String) throws -> TMDBMovieDetails {
        let decoder = JSONDecoder()
        return try decoder.decode(TMDBMovieDetails.self, from: Data(json.utf8))
    }

    @Test func decodesVoteCount() throws {
        let details = try decode("""
            {"id":1,"title":"A","genres":[],"vote_average":7.4,"vote_count":5123}
            """)
        #expect(details.voteCount == 5123)
        #expect(details.voteAverage == 7.4)
    }

    @Test func missingVoteCountIsNil() throws {
        let details = try decode(#"{"id":1,"title":"A","genres":[]}"#)
        #expect(details.voteCount == nil)
    }

    @Test func memberwiseInitDefaultsToNil() {
        let details = TMDBMovieDetails(id: 1, title: "A", releaseDate: nil, overview: nil,
                                       posterPath: nil, backdropPath: nil, runtime: nil,
                                       genres: [], voteAverage: nil)
        #expect(details.voteCount == nil)
        let counted = TMDBMovieDetails(id: 1, title: "A", releaseDate: nil, overview: nil,
                                       posterPath: nil, backdropPath: nil, runtime: nil,
                                       genres: [], voteAverage: 8, voteCount: 300)
        #expect(counted.voteCount == 300)
    }
}
