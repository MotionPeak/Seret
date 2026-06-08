import Testing
import Foundation
import DebridCore
@testable import DebridUI

@MainActor
struct RatingsDetailStoreTests {
    // Minimal MediaDetailsProviding that returns a movie carrying an imdbID.
    struct StubDetails: MediaDetailsProviding {
        func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
            TMDBMovieDetails(id: tmdbID, title: "M", releaseDate: "2020-01-01", overview: "o",
                             posterPath: nil, backdropPath: nil, runtime: 100, genres: [],
                             voteAverage: 7.0, originalLanguage: "en", imdbID: "tt123")
        }
        func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw CancellationError() }
        func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
    }
    struct OKRatings: RatingsProviding {
        let value: OMDbRatings
        func ratings(imdbID: String) async throws -> OMDbRatings { value }
    }
    struct FailRatings: RatingsProviding {
        func ratings(imdbID: String) async throws -> OMDbRatings { throw OMDbError.notFound("x") }
    }

    private func movie() -> MediaItem {
        MediaItem(id: "1", kind: .movie, title: "M", year: 2020, sources: [], seasons: [],
                  tmdbID: 99, overview: nil)
    }

    @Test func loadPopulatesRatings() async {
        let sample = OMDbRatings(imdb: 8.7, rottenTomatoes: 88, metacritic: 73)
        let store = DetailStore(item: movie(), details: StubDetails(), watch: nil,
                                ratings: OKRatings(value: sample))
        await store.load()
        #expect(store.ratings == sample)
        #expect(store.ratingsState == .loaded)
    }

    @Test func ratingsFailureDegradesGracefully() async {
        let store = DetailStore(item: movie(), details: StubDetails(), watch: nil,
                                ratings: FailRatings())
        await store.load()
        #expect(store.ratings == nil)
        #expect(store.ratingsState == .failed)
        #expect(store.richState == .loaded)   // the rest of the screen still loads
    }

    @Test func noProviderLeavesRatingsIdle() async {
        let store = DetailStore(item: movie(), details: StubDetails(), watch: nil)
        await store.load()
        #expect(store.ratings == nil)
        #expect(store.ratingsState == .idle)
    }
}
