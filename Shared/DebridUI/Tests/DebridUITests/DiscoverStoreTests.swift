import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

/// Records calls and returns canned, UNIQUE-id results per call (so the store's cross-rail dedup
/// doesn't shrink rail counts in assertions).
private final class FakeDiscover: DiscoverProviding, @unchecked Sendable {
    var failGenres = false
    private(set) var calledTrending = false
    private(set) var calledTopRatedCurated = false
    private let lock = NSLock()
    private var _recommendedFor: [Int] = []
    var recommendedFor: [Int] { lock.withLock { _recommendedFor } }

    // Unique ids are derived from the arguments (genre id / decade year), NOT a shared counter —
    // the rails are fetched concurrently, so a mutating counter would race and collide.
    func nowPlayingMovies() async throws -> [TMDBSearchResult] { [movie(7), movie(8)] }
    func trending(_ kind: MediaKind, window: TMDBTrendingWindow) async throws -> [TMDBSearchResult] {
        calledTrending = true
        return window == .day ? [movie(9001)] : [movie(9002)]
    }
    func topRatedCurated(_ kind: MediaKind) async throws -> [TMDBSearchResult] {
        calledTopRatedCurated = true; return [movie(9100)]
    }
    func newOverall(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] { [movie(9200)] }
    func decade(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] {
        [movie(40000 + (Int(from.prefix(4)) ?? 0))]
    }
    func recommended(_ kind: MediaKind, tmdbID: Int) async throws -> [TMDBSearchResult] {
        lock.withLock { _recommendedFor.append(tmdbID) }
        return [movie(70000 + tmdbID)]
    }
    func newByGenre(_ kind: MediaKind, _ genreID: Int, from: String, to: String) async throws -> [TMDBSearchResult] {
        if failGenres { throw FakeError.boom }; return [movie(10000 + genreID)]
    }
    func popularByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult] {
        if failGenres { throw FakeError.boom }; return [movie(20000 + genreID)]
    }
    func topRatedByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult] {
        if failGenres { throw FakeError.boom }; return [movie(30000 + genreID)]
    }
}

@MainActor
private final class FakeSeeds: RecommendationSeedProviding {
    var value: [RecommendationSeed] = []
    func seeds(kind: MediaKind, limit: Int) async -> [RecommendationSeed] { value }
}

private func movie(_ id: Int) -> TMDBSearchResult {
    TMDBSearchResult(id: id, title: "M\(id)", name: nil, releaseDate: "2020-01-01",
                     firstAirDate: nil, posterPath: "/p.jpg", overview: nil, voteAverage: 7)
}

@MainActor
@Suite struct DiscoverStoreTests {
    @Test func lazyLoadsOnlyTheRequestedSegment() async {
        let fake = FakeDiscover()
        let store = DiscoverStore(kind: .movie, discover: fake)
        await store.loadSegment(.popular)
        #expect(store.segmentState(.popular) == .loaded)
        #expect(store.segmentState(.trending) == .idle)
        #expect(fake.calledTrending == false)
    }

    @Test func popularHasOneRailPerMovieGenre() async {
        let store = DiscoverStore(kind: .movie, discover: FakeDiscover())
        await store.loadSegment(.popular)
        #expect(store.rowsBySegment[.popular]?.count == DiscoverStore.movieGenreCount)
    }

    @Test func topRatedHasCuratedPlusDecadesPlusGenres() async {
        let store = DiscoverStore(kind: .movie, discover: FakeDiscover())
        await store.loadSegment(.topRated)
        let rows = store.rowsBySegment[.topRated] ?? []
        #expect(rows.count == 1 + DiscoverStore.decadeCount + DiscoverStore.movieGenreCount)
        #expect(rows.first?.title == "Top Rated of All Time")
    }

    @Test func trendingHasTodayAndThisWeek() async {
        let fake = FakeDiscover()
        let store = DiscoverStore(kind: .movie, discover: fake)
        await store.loadSegment(.trending)
        let titles = (store.rowsBySegment[.trending] ?? []).map(\.title)
        #expect(titles == ["Trending Today", "Trending This Week"])
        #expect(fake.calledTrending)
    }

    @Test func failedGenreRailsAreDroppedNotFatal() async {
        let fake = FakeDiscover(); fake.failGenres = true
        let store = DiscoverStore(kind: .movie, discover: fake)
        await store.loadSegment(.popular)
        #expect(store.rowsBySegment[.popular]?.isEmpty == true)
        #expect(store.segmentState(.popular) == .failed)
    }

    @Test func camIDsLoadedForMovies() async {
        let store = DiscoverStore(kind: .movie, discover: FakeDiscover())
        await store.loadSegment(.popular)
        #expect(store.camIDs == [7, 8])
    }

    @Test func forYouBuildsBecauseYouWatchedAndMoreLike() async {
        let fake = FakeDiscover()
        let seeds = FakeSeeds()
        seeds.value = [RecommendationSeed(tmdbID: 100, title: "Dune", watched: true),
                       RecommendationSeed(tmdbID: 200, title: "Heat", watched: false)]
        let store = DiscoverStore(kind: .movie, discover: fake, seeds: seeds)
        await store.loadSegment(.forYou)
        let titles = (store.rowsBySegment[.forYou] ?? []).map(\.title)
        #expect(titles.contains("Because you watched Dune"))
        #expect(titles.contains("More like Heat"))
        #expect(Set(fake.recommendedFor) == [100, 200])
    }

    @Test func forYouFallsBackToTrendingWhenNoSeeds() async {
        let fake = FakeDiscover()
        let store = DiscoverStore(kind: .movie, discover: fake, seeds: FakeSeeds())
        await store.loadSegment(.forYou)
        let titles = (store.rowsBySegment[.forYou] ?? []).map(\.title)
        #expect(titles == ["Trending Today", "Trending This Week"])
    }
}
