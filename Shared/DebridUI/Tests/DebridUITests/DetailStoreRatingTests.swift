import Testing
import Foundation
import DebridCore
@testable import DebridUI

/// The personal (Trakt) rating on Detail — separate from the aggregate OMDb scores.
@MainActor
@Suite struct DetailStoreRatingTests {
    /// Implements BOTH seams, like the real TraktWatchProvider, so DetailStore's conditional cast
    /// picks it up without any extra injection.
    final class FakeWatchWithRatings: WatchProgressProviding, WatchRatingProviding, @unchecked Sendable {
        var ratings: [String: Int] = [:]
        private(set) var writes: [(String, Int?)] = []

        func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { nil }
        func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                    durationSeconds: Double, finished: Bool, profileID: String) async throws {}
        func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
        func deleteProgress(forContentKeys keys: [String]) async throws {}

        func rating(forContentKey key: String) async -> Int? { ratings[key] }
        func setRating(_ value: Int?, forContentKey key: String) async {
            writes.append((key, value))
            ratings[key] = value
        }
    }

    /// A watch backend with NO rating support — the rating control must stay hidden.
    struct PlainWatch: WatchProgressProviding {
        func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { nil }
        func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                    durationSeconds: Double, finished: Bool, profileID: String) async throws {}
        func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
        func deleteProgress(forContentKeys keys: [String]) async throws {}
    }

    private func movie() -> MediaItem {
        MediaItem(id: "movie:tmdb:693134", kind: .movie, title: "Dune", year: 2024,
                  sources: [], seasons: [], tmdbID: 693134)
    }
    private func show() -> MediaItem {
        MediaItem(id: "show:tmdb:1399", kind: .show, title: "GoT", year: 2011,
                  sources: [], seasons: [], tmdbID: 1399)
    }

    @Test func loadsExistingRating() async {
        let watch = FakeWatchWithRatings()
        watch.ratings["movie:tmdb:693134"] = 8
        let store = DetailStore(item: movie(), details: PreviewDetailsStub(), watch: watch)
        #expect(store.canRate)
        await store.loadUserRating()
        #expect(store.userRating == 8)
    }

    @Test func ratingWritesThroughAndUpdatesOptimistically() async {
        let watch = FakeWatchWithRatings()
        let store = DetailStore(item: movie(), details: PreviewDetailsStub(), watch: watch)
        await store.rate(9)
        #expect(store.userRating == 9)
        #expect(watch.writes.count == 1)
        #expect(watch.writes[0].0 == "movie:tmdb:693134")
        #expect(watch.writes[0].1 == 9)
    }

    @Test func clearingRatingWritesNil() async {
        let watch = FakeWatchWithRatings()
        watch.ratings["movie:tmdb:693134"] = 7
        let store = DetailStore(item: movie(), details: PreviewDetailsStub(), watch: watch)
        await store.rate(nil)
        #expect(store.userRating == nil)
        #expect(watch.writes[0].1 == nil)
    }

    @Test func unavailableWithoutARatingBackend() async {
        let store = DetailStore(item: movie(), details: PreviewDetailsStub(), watch: PlainWatch())
        #expect(store.canRate == false)
        await store.rate(5)
        #expect(store.userRating == nil)      // no backend → no-op
    }

    @Test func showsRateAgainstTheSeriesKey() async {
        let watch = FakeWatchWithRatings()
        let store = DetailStore(item: show(), details: PreviewDetailsStub(), watch: watch)
        #expect(store.canRate)
        await store.rate(10)
        #expect(store.userRating == 10)
        #expect(watch.writes[0].0 == "show:tmdb:1399")   // the series itself, not an episode
    }

    @Test func unenrichedTitleCannotBeRated() async {
        // No tmdbID → no Trakt identity → the control stays hidden.
        let item = MediaItem(id: "movie:dune:2024", kind: .movie, title: "Dune", year: 2024,
                             sources: [], seasons: [], tmdbID: nil)
        let store = DetailStore(item: item, details: PreviewDetailsStub(), watch: FakeWatchWithRatings())
        #expect(store.canRate == false)
    }
}

/// Minimal details provider so the store can be constructed.
struct PreviewDetailsStub: MediaDetailsProviding {
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
        TMDBMovieDetails(id: tmdbID, title: "M", releaseDate: "2024-01-01", overview: nil,
                         posterPath: nil, backdropPath: nil, runtime: 100, genres: [],
                         voteAverage: 7.0, originalLanguage: "en", imdbID: nil)
    }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw CancellationError() }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
}
