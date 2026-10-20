import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

/// Records calls and returns canned, UNIQUE-id results per call (so the store's cross-rail dedup
/// doesn't shrink rail counts in assertions).
private final class FakeDiscover: DiscoverProviding, @unchecked Sendable {
    var failGenres = false
    /// Every call throws — the page's failed state.
    var failAll = false
    /// When set, every genre's popular titles include this id — twice (a within-row duplicate),
    /// and in every genre (a cross-row duplicate).
    var sharedGenreHit: Int?
    /// Holds ONE seed's recommendations until opened, so a For You rebuild can be caught in flight.
    var recommendGate: DiscoverGate?
    var gatedRecommendation: Int?
    private var _popularCalls = 0
    var popularCalls: Int { lock.withLock { _popularCalls } }
    private(set) var calledTrending = false
    private(set) var calledTopRatedCurated = false
    private let lock = NSLock()
    private var _recommendedFor: [Int] = []
    var recommendedFor: [Int] { lock.withLock { _recommendedFor } }

    // Unique ids are derived from the arguments (genre id / decade year), NOT a shared counter —
    // the rails are fetched concurrently, so a mutating counter would race and collide.
    func nowPlayingMovies() async throws -> [TMDBSearchResult] { [movie(7), movie(8)] }
    /// Holds the Trending fetches until opened, so a load can be caught in flight — only
    /// `gatedWindow`'s, when set, so one rail can land while the other is still fetching.
    var trendingGate: DiscoverGate?
    var gatedWindow: TMDBTrendingWindow?
    func trending(_ kind: MediaKind, window: TMDBTrendingWindow) async throws -> [TMDBSearchResult] {
        if failAll { throw FakeError.boom }
        calledTrending = true
        if let trendingGate, gatedWindow == nil || gatedWindow == window { await trendingGate.wait() }
        return window == .day ? [movie(9001)] : [movie(9002)]
    }
    func topRatedCurated(_ kind: MediaKind) async throws -> [TMDBSearchResult] {
        if failAll { throw FakeError.boom }
        calledTopRatedCurated = true; return [movie(9100)]
    }
    func newOverall(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] {
        if failAll { throw FakeError.boom }
        return [movie(9200)]
    }
    func decade(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] {
        [movie(40000 + (Int(from.prefix(4)) ?? 0))]
    }
    func recommended(_ kind: MediaKind, tmdbID: Int) async throws -> [TMDBSearchResult] {
        if failAll { throw FakeError.boom }
        lock.withLock { _recommendedFor.append(tmdbID) }
        if let recommendGate, gatedRecommendation == tmdbID { await recommendGate.wait() }
        return [movie(70000 + tmdbID)]
    }
    func newByGenre(_ kind: MediaKind, _ genreID: Int, from: String, to: String) async throws -> [TMDBSearchResult] {
        if failGenres { throw FakeError.boom }; return [movie(10000 + genreID)]
    }
    func popularByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult] {
        lock.withLock { _popularCalls += 1 }
        if failGenres || failAll { throw FakeError.boom }
        if let shared = sharedGenreHit { return [movie(shared), movie(20000 + genreID), movie(shared)] }
        return [movie(20000 + genreID)]
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
        await store.refreshForYouIfBetterSeeds()      // the page calls this when the library lands

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
        await store.refreshForYouIfBetterSeeds()

        #expect((store.rowsBySegment[.forYou] ?? []).map(\.title)
                == ["Because you watched Dune", "More like Heat"])
    }

    /// The launch race itself: the library lands WHILE For You's first build is still fetching, and
    /// the page asks for a refresh at that moment. The refresh found the build "loading" and gave up
    /// — and the build had been made from the seeds there were when it started: none. Trending for
    /// the session.
    @Test func seedsArrivingDuringTheFirstBuildStillMakeForYouPersonal() async {
        let fake = FakeDiscover()
        let gate = DiscoverGate()
        fake.trendingGate = gate
        let seeds = FakeSeeds()                                 // the first build finds no seeds
        let store = DiscoverStore(kind: .movie, discover: fake, seeds: seeds)

        let first = Task { await store.loadSegment(.forYou) }
        for _ in 0..<200 where !fake.calledTrending { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(store.segmentState(.forYou) == .loading)
        seeds.value = [RecommendationSeed(tmdbID: 100, title: "Dune", watched: true)]
        let refresh = Task { await store.refreshForYouIfBetterSeeds() }   // the page's onChange
        try? await Task.sleep(for: .milliseconds(20))
        await gate.open()
        await first.value
        await refresh.value

        #expect((store.rowsBySegment[.forYou] ?? []).map(\.title) == ["Because you watched Dune"])
    }

    /// …and once its first rail is on screen — the build reads "loaded" while the rest are still
    /// coming in. The refresh joined that build and stopped there.
    @Test func seedsArrivingAsTheFirstBuildFinishesStillMakeForYouPersonal() async {
        let fake = FakeDiscover()
        let gate = DiscoverGate()
        fake.trendingGate = gate
        fake.gatedWindow = .week                                // Today lands, This Week waits
        let seeds = FakeSeeds()
        let store = DiscoverStore(kind: .movie, discover: fake, seeds: seeds)

        let first = Task { await store.loadSegment(.forYou) }
        for _ in 0..<200 where store.segmentState(.forYou) != .loaded {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect((store.rowsBySegment[.forYou] ?? []).map(\.title) == ["Trending Today"])
        seeds.value = [RecommendationSeed(tmdbID: 100, title: "Dune", watched: true)]
        let refresh = Task { await store.refreshForYouIfBetterSeeds() }
        try? await Task.sleep(for: .milliseconds(20))
        await gate.open()
        await first.value
        await refresh.value

        #expect((store.rowsBySegment[.forYou] ?? []).map(\.title) == ["Because you watched Dune"])
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
        await store.refreshForYouIfBetterSeeds()

        #expect(fake.recommendedFor.count == asked)
    }

    /// Coming back to For You re-runs the page's load: that alone must never rebuild it. The rebuild
    /// used to hang off the load, so a return emptied the rails into skeletons under the viewer.
    @Test func askingForAFallbackForYouAgainDoesNotRebuildIt() async {
        let fake = FakeDiscover()
        let seeds = FakeSeeds()
        let store = DiscoverStore(kind: .movie, discover: fake, seeds: seeds)
        await store.loadSegment(.forYou)
        seeds.value = [RecommendationSeed(tmdbID: 100, title: "Dune", watched: true)]

        await store.loadSegment(.forYou)                // a return to the page, not a seed change

        #expect((store.rowsBySegment[.forYou] ?? []).map(\.title).first == "Trending Today")
        #expect(fake.recommendedFor.isEmpty)
    }
}

/// Lets the store's own tasks run until `condition` holds — no wall-clock sleeps.
@MainActor
private func spin(until condition: () -> Bool) async {
    for _ in 0..<200_000 where !condition() { await Task.yield() }
}

/// The Apple TV's Movies/Shows page: ONE list of rows (no segments) — For You, Trending, New, Top
/// Rated, then a row per genre, Netflix-style. Additive: the segment API the iPhone and Mac use
/// must not change under it.
@MainActor
@Suite struct DiscoverBrowsePageTests {
    private let fixed = ["Trending This Week", "New This Month", "Top Rated of All Time"]

    @Test func moviePageOrderIsForYouThenTrendingNewTopRatedThenOneRowPerGenre() async {
        let seeds = FakeSeeds()
        seeds.value = [RecommendationSeed(tmdbID: 100, title: "Dune", watched: true),
                       RecommendationSeed(tmdbID: 200, title: "Heat", watched: false)]
        let store = DiscoverStore(kind: .movie, discover: FakeDiscover(), seeds: seeds)
        await store.loadBrowsePage()

        let genreNames = DiscoverStore.genres(for: .movie).map(\.name)
        #expect(store.browseState == .loaded)
        #expect(store.browseRows.map(\.title)
                == ["Because you watched Dune", "More like Heat"] + fixed + genreNames)
        #expect(genreNames.contains("Drama") && genreNames.contains("Fantasy") && genreNames.contains("Sci-Fi"))
    }

    @Test func showPageUsesTheTVGenreTable() async {
        let store = DiscoverStore(kind: .show, discover: FakeDiscover(), seeds: FakeSeeds())
        await store.loadBrowsePage()

        #expect(store.browseRows.map(\.title)
                == fixed + DiscoverStore.genres(for: .show).map(\.name))
    }

    /// Genre rows carry their genre — the "See All" tile at a row's end opens that genre's grid —
    /// and hold the genre's popular titles. The fixed rows have no genre.
    @Test func genreRowsCarryTheirGenreAndItsPopularTitles() async {
        let store = DiscoverStore(kind: .movie, discover: FakeDiscover(), seeds: FakeSeeds())
        await store.loadBrowsePage()

        let genres = DiscoverStore.genres(for: .movie)
        let genreRows = store.browseRows.filter { $0.genre != nil }
        #expect(genreRows.map(\.genre) == genres)
        #expect(genreRows.map { $0.hits.map(\.result.id) } == genres.map { [20000 + $0.tmdbID] })
        #expect(store.browseRows.prefix(3).allSatisfy { $0.genre == nil })
    }

    /// At most three personal rows, however many seeds there are.
    @Test func forYouIsCappedAtThreeRows() async {
        let seeds = FakeSeeds()
        seeds.value = (1...6).map { RecommendationSeed(tmdbID: $0, title: "S\($0)", watched: true) }
        let store = DiscoverStore(kind: .movie, discover: FakeDiscover(), seeds: seeds)
        await store.loadBrowsePage()

        #expect(store.browseRows.prefix(4).map(\.title)
                == ["Because you watched S1", "Because you watched S2", "Because you watched S3",
                    "Trending This Week"])
    }

    /// Netflix shows a title in Drama AND in Thriller — rows are not de-duplicated against each
    /// other. Inside one row a title still appears once.
    @Test func aTitleMayRepeatAcrossRowsButNeverWithinOne() async {
        let fake = FakeDiscover()
        fake.sharedGenreHit = 555
        let store = DiscoverStore(kind: .movie, discover: fake, seeds: FakeSeeds())
        await store.loadBrowsePage()

        let genreRows = store.browseRows.filter { $0.genre != nil }
        #expect(genreRows.count == DiscoverStore.movieGenreCount)
        for row in genreRows {
            #expect(row.hits.filter { $0.result.id == 555 }.count == 1, "\(row.title)")
            #expect(Set(row.hits.map(\.id)).count == row.hits.count, "\(row.title)")
        }
    }

    /// Rows arrive progressively, and only ever at the bottom: a row that finishes early waits
    /// behind an unfinished one above it, so nothing on screen moves. The page shows as soon as the
    /// first row has content.
    @Test func thePageShowsEarlyAndGrowsOnlyAtTheBottom() async {
        let fake = FakeDiscover()
        let gate = DiscoverGate()
        fake.trendingGate = gate                                   // Trending This Week waits
        let seeds = FakeSeeds()
        seeds.value = [RecommendationSeed(tmdbID: 100, title: "Dune", watched: true)]
        let store = DiscoverStore(kind: .movie, discover: fake, seeds: seeds)

        let load = Task { await store.loadBrowsePage() }
        await spin { store.browseState == .loaded }
        // Every other row can finish meanwhile — none of them may show above the gated one.
        await spin { fake.popularCalls >= 6 }
        for _ in 0..<1_000 { await Task.yield() }

        #expect(store.browseState == .loaded)
        let early = store.browseRows.map(\.title)
        #expect(early == ["Because you watched Dune"])

        await gate.open()
        await load.value
        let full = store.browseRows.map(\.title)
        #expect(Array(full.prefix(early.count)) == early)
        #expect(full.count == 1 + 3 + DiscoverStore.movieGenreCount)
    }

    /// When better seeds arrive (the library, then the watch history), only the For You block is
    /// rebuilt — quietly: the rows on screen stay until the new block is in, then it is swapped in
    /// one step. Nothing below the block is fetched again or changes.
    @Test func betterSeedsReplaceOnlyTheForYouBlockInOneStep() async {
        let fake = FakeDiscover()
        let seeds = FakeSeeds()
        seeds.value = [RecommendationSeed(tmdbID: 200, title: "Heat", watched: false)]
        let store = DiscoverStore(kind: .movie, discover: fake, seeds: seeds)
        await store.loadBrowsePage()
        let before = store.browseRows
        #expect(before.first?.title == "More like Heat")
        let popularCalls = fake.popularCalls

        let gate = DiscoverGate()
        fake.recommendGate = gate
        fake.gatedRecommendation = 100
        seeds.value = [RecommendationSeed(tmdbID: 100, title: "Dune", watched: true),
                       RecommendationSeed(tmdbID: 200, title: "Heat", watched: false)]
        let refresh = Task { await store.refreshForYouIfBetterSeeds() }
        await spin { fake.recommendedFor.contains(100) }
        for _ in 0..<1_000 { await Task.yield() }
        #expect(store.browseRows == before, "the old block stays until the new one is all in")
        #expect(store.browseState == .loaded)

        await gate.open()
        await refresh.value
        #expect(store.browseRows.map(\.title)
                == ["Because you watched Dune", "More like Heat"] + before.dropFirst().map(\.title))
        #expect(Array(store.browseRows.dropFirst(2)) == Array(before.dropFirst()))
        #expect(fake.popularCalls == popularCalls, "only the For You block is fetched again")
    }

    /// No seeds yet (the library had not loaded): no personal rows — Trending leads. When seeds
    /// arrive, the For You block is added above it.
    @Test func aPageBuiltWithoutSeedsGainsForYouWhenTheyArrive() async {
        let seeds = FakeSeeds()
        let store = DiscoverStore(kind: .movie, discover: FakeDiscover(), seeds: seeds)
        await store.loadBrowsePage()
        let before = store.browseRows
        #expect(before.first?.title == "Trending This Week")

        seeds.value = [RecommendationSeed(tmdbID: 100, title: "Dune", watched: true)]
        await store.refreshForYouIfBetterSeeds()

        #expect(store.browseRows.map(\.title) == ["Because you watched Dune"] + before.map(\.title))
    }

    @Test func aPersonalPageIsNotRebuiltOnEveryAsk() async {
        let fake = FakeDiscover()
        let seeds = FakeSeeds()
        seeds.value = [RecommendationSeed(tmdbID: 100, title: "Dune", watched: true)]
        let store = DiscoverStore(kind: .movie, discover: fake, seeds: seeds)
        await store.loadBrowsePage()
        let asked = fake.recommendedFor.count

        await store.loadBrowsePage()
        await store.refreshForYouIfBetterSeeds()

        #expect(fake.recommendedFor.count == asked)
    }

    @Test func aPageWithNothingToShowFailsAndRetryReloadsIt() async {
        let fake = FakeDiscover()
        fake.failAll = true
        let store = DiscoverStore(kind: .movie, discover: fake, seeds: FakeSeeds())
        await store.loadBrowsePage()
        #expect(store.browseState == .failed)
        #expect(store.browseRows.isEmpty)

        fake.failAll = false
        await store.loadBrowsePage()                    // Retry
        #expect(store.browseState == .loaded)
        #expect(store.browseRows.first?.title == "Trending This Week")
    }

    /// The page and the segments are separate: the iPhone and the Mac still browse by segment, and
    /// loading one never touches the other.
    @Test func thePageLeavesTheSegmentsAlone() async {
        let store = DiscoverStore(kind: .movie, discover: FakeDiscover(), seeds: FakeSeeds())
        await store.loadBrowsePage()
        #expect(store.rowsBySegment.isEmpty)
        for segment in DiscoverStore.Segment.allCases { #expect(store.segmentState(segment) == .idle) }
        #expect(store.camIDs == [7, 8])

        await store.loadSegment(.popular)
        #expect(store.browseRows.count == 3 + DiscoverStore.movieGenreCount)
        #expect(store.rowsBySegment[.popular]?.map(\.title).first == "Popular in Action")
        #expect(store.rowsBySegment[.popular]?.allSatisfy { $0.genre == nil } == true)
    }
}
