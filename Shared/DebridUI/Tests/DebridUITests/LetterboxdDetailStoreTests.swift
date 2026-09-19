import Testing
import Foundation
import DebridCore
@testable import DebridUI

@MainActor
struct LetterboxdDetailStoreTests {
    private struct StubDetails: MediaDetailsProviding {
        func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
            TMDBMovieDetails(id: tmdbID, title: "M", releaseDate: "2020-01-01", overview: "o",
                             posterPath: nil, backdropPath: nil, runtime: 100, genres: [],
                             voteAverage: 7.0, originalLanguage: "en", imdbID: nil)
        }
        func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
            TMDBTVDetails(id: tmdbID, name: "S", firstAirDate: "2020-01-01", overview: "o",
                          posterPath: nil, backdropPath: nil, numberOfSeasons: 1,
                          genres: [], voteAverage: 8.0)
        }
        func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
    }

    private actor Calls {
        private(set) var count = 0
        func bump() { count += 1 }
    }

    private struct CountingProvider: LetterboxdRatingProviding {
        let calls: Calls
        let result: LetterboxdFilmRating?
        let error: (any Error)?

        func rating(forTMDB id: Int) async throws -> LetterboxdFilmRating? {
            await calls.bump()
            if let error { throw error }
            return result
        }
    }

    private func provider(_ calls: Calls, _ result: LetterboxdFilmRating? = nil,
                          error: (any Error)? = nil) -> CountingProvider {
        CountingProvider(calls: calls, result: result, error: error)
    }

    private func movie(tmdbID: Int? = 99) -> MediaItem {
        MediaItem(id: "1", kind: .movie, title: "M", year: 2020, sources: [], seasons: [],
                  tmdbID: tmdbID, overview: nil)
    }

    private func show() -> MediaItem {
        MediaItem(id: "2", kind: .show, title: "S", year: 2020, sources: [], seasons: [],
                  tmdbID: 1396, overview: nil)
    }

    private let sample = LetterboxdFilmRating(score: 4.38, count: 3_654_485)

    @Test func aMoviesScoreLoadsIntoTheStore() async {
        let calls = Calls()
        let store = DetailStore(item: movie(), details: StubDetails(), watch: nil,
                                letterboxd: provider(calls, sample))
        await store.load()
        #expect(store.letterboxdRating == sample)
        #expect(store.letterboxdState == .loaded)
        #expect(await calls.count == 1)
    }

    /// Letterboxd indexes films only. Asking about a show spends a request to be told no, on every
    /// single title-page open, so the store must not ask at all.
    @Test func aShowIsNeverAskedAbout() async {
        let calls = Calls()
        let store = DetailStore(item: show(), details: StubDetails(), watch: nil,
                                letterboxd: provider(calls, sample))
        await store.load()
        #expect(store.letterboxdRating == nil)
        #expect(store.letterboxdState == .idle)
        #expect(await calls.count == 0)
    }

    /// The TMDB id is the only id Letterboxd can be reached by; without one there is nothing to ask.
    @Test func aMovieWithNoTMDBIdIsNeverAskedAbout() async {
        let calls = Calls()
        let store = DetailStore(item: movie(tmdbID: nil), details: StubDetails(), watch: nil,
                                letterboxd: provider(calls, sample))
        await store.load()
        #expect(await calls.count == 0)
    }

    @Test func aFailureLeavesTheRestOfThePageIntact() async {
        let store = DetailStore(item: movie(), details: StubDetails(), watch: nil,
                                letterboxd: provider(Calls(), error: LetterboxdError.transient("x")))
        await store.load()
        #expect(store.letterboxdRating == nil)
        #expect(store.letterboxdState == .failed)
        #expect(store.richState == .loaded)
    }

    @Test func noProviderLeavesItIdle() async {
        let store = DetailStore(item: movie(), details: StubDetails(), watch: nil)
        await store.load()
        #expect(store.letterboxdRating == nil)
        #expect(store.letterboxdState == .idle)
    }
}
