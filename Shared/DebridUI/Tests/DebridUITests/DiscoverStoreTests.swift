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
    /// Holds the Trending fetches until opened, so a load can be caught in flight.
    var trendingGate: DiscoverGate?
    func trending(_ kind: MediaKind, window: TMDBTrendingWindow) async throws -> [TMDBSearchResult] {
        calledTrending = true
        if let trendingGate { await trendingGate.wait() }
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

private actor DiscoverGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var opened = false
    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        for w in waiters { w.resume() }
        waiters = []
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

    /// The browse pages are built at launch — kept alive behind Home — so For You was asked for
    /// before the library had loaded, found no seeds, fell back to Trending, and was then cached as
    /// loaded: personal rails never appeared for the rest of the session. A fallback is now rebuilt
    /// the next time it is asked for once there is something to seed it.
    @Test func aFallbackForYouIsRebuiltOnceSeedsArrive() async {
        let fake = FakeDiscover()
        let seeds = FakeSeeds()                       // the library has not loaded yet
        let store = DiscoverStore(kind: .movie, discover: fake, seeds: seeds)
        await store.loadSegment(.forYou)
        #expect((store.rowsBySegment[.forYou] ?? []).map(\.title).first == "Trending Today")

        seeds.value = [RecommendationSeed(tmdbID: 100, title: "Dune", watched: true)]
        await store.loadSegment(.forYou)              // the page asks again when the library lands

        #expect((store.rowsBySegment[.forYou] ?? []).map(\.title) == ["Because you watched Dune"])
    }

    /// The load ran inside the asking VIEW's task, so leaving the segment cancelled it — and an ask
    /// that landed while it was still unwinding found the segment "loading" and returned, after
    /// which the cancelled load set it back to idle. Nobody was loading any more: skeletons for good,
    /// the "segment left mid-load comes back empty" report. The store owns the load now.
    @Test func aLoadWhoseCallerWentAwayStillFinishes() async {
        let fake = FakeDiscover()
        let gate = DiscoverGate()
        fake.trendingGate = gate
        let store = DiscoverStore(kind: .movie, discover: fake)

        let first = Task { await store.loadSegment(.trending) }
        for _ in 0..<200 where store.segmentState(.trending) != .loading {
            try? await Task.sleep(for: .milliseconds(5))
        }
        first.cancel()                                        // the view's task goes away…
        let second = Task { await store.loadSegment(.trending) }   // …and the next one asks at once
        try? await Task.sleep(for: .milliseconds(20))
        await gate.open()
        await second.value
        await first.value

        #expect(store.segmentState(.trending) == .loaded)
        #expect((store.rowsBySegment[.trending] ?? []).map(\.title) == ["Trending Today",
                                                                         "Trending This Week"])
    }

    /// The library can land before the profile does: For You is then built from library titles
    /// ("More like…") with no watch history, and must become "Because you watched…" once there is
    /// history to go on — measured on launch, where the cached library won that race.
    @Test func aLibraryOnlyForYouIsRebuiltOnceHistoryArrives() async {
        let fake = FakeDiscover()
        let seeds = FakeSeeds()
        seeds.value = [RecommendationSeed(tmdbID: 200, title: "Heat", watched: false)]
        let store = DiscoverStore(kind: .movie, discover: fake, seeds: seeds)
        await store.loadSegment(.forYou)
        #expect((store.rowsBySegment[.forYou] ?? []).map(\.title) == ["More like Heat"])

        seeds.value = [RecommendationSeed(tmdbID: 100, title: "Dune", watched: true),
                       RecommendationSeed(tmdbID: 200, title: "Heat", watched: false)]
        await store.loadSegment(.forYou)

        #expect((store.rowsBySegment[.forYou] ?? []).map(\.title)
                == ["Because you watched Dune", "More like Heat"])
    }

    /// …and a For You built from real seeds is not rebuilt just because it is asked for again.
    @Test func aPersonalForYouIsNotRebuiltOnEveryAsk() async {
        let fake = FakeDiscover()
        let seeds = FakeSeeds()
        seeds.value = [RecommendationSeed(tmdbID: 100, title: "Dune", watched: true)]
        let store = DiscoverStore(kind: .movie, discover: fake, seeds: seeds)
        await store.loadSegment(.forYou)
        let asked = fake.recommendedFor.count

        await store.loadSegment(.forYou)

        #expect(fake.recommendedFor.count == asked)
    }
}
