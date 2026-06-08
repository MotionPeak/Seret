# Bigger, Better Browse — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Movies/TV browse tabs deep and personalized — real TMDB trending/top-rated endpoints, all genres, more titles per rail, decade rails, and a "For You" segment of recommendations seeded from what the user has watched and owns.

**Architecture:** Add the missing TMDB endpoints to `DebridCore/TMDBClient`. Reshape the `DiscoverProviding` seam to be kind-parameterized and fetch 2 pages per rail. Rewrite `DiscoverStore` for 5 lazy-loaded segments (For You · Trending · New · Popular · Top Rated) across all genres. Add a `RecommendationSeedProviding` seam (watched-first, then library) that feeds "For You". Both apps' `BrowseScreen` switch to lazy per-segment loading with an always-visible segment picker.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI. No new third-party dependencies. Mainstream-global content (high vote floors, no language filter).

**Branch:** build on current `feat/profiles`. **Stage only the paths in each task's commit step** — never `git add -A` (parallel profiles WIP lives here).

**Spec:** `docs/superpowers/specs/2026-06-08-bigger-browse-design.md`

> **Design refinement vs spec:** to avoid two identical segments, **Trending** is the two real `/trending` rails only (Today + This Week) — per-genre popularity rows live under **Popular** (a genre popularity sort would be identical in both). All other spec content stands.

---

## File Structure

**DebridCore**
- `Metadata/TMDBClient.swift` (modify) — new endpoints (`trending`, curated `top_rated`, `recommendations`, decade, TV new-overall), `page` params, raised genre vote floors, `TMDBTrendingWindow` enum.
- `Tests/DebridCoreTests/TMDBClientTests.swift` (extend) — URL + decode tests for the new calls.

**DebridUI**
- `Search/DiscoverStore.swift` (rewrite) — `DiscoverProviding` (kind-parameterized) + `TMDBDiscoverService` (2-page paging) + `DiscoverStore` (5 segments, lazy per-segment, all genres, curated + decade + For-You rails).
- `Search/RecommendationSeedProviding.swift` (create) — seam + `RecommendationSeedService`.
- `Shell/AppSession.swift` (modify) — compose the seed service, inject into both `DiscoverStore`s.
- `Tests/DebridUITests/DiscoverStoreTests.swift` (rewrite) — lazy per-segment, all-genre coverage, curated/decade rails, For-You seeding/dedup/fallback.
- `Tests/DebridUITests/RecommendationSeedServiceTests.swift` (create).

**Apps**
- `Apps/SeretTV/Browse/BrowseScreen.swift` (modify) — always-visible 5-segment picker, lazy per-segment load.
- `Apps/SeretMobile/Browse/BrowseScreen.swift` (modify) — same.

---

# SLICE 1 — DebridCore TMDB endpoints

## Task 1: New TMDB endpoints + paging + raised vote floors

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Metadata/TMDBClient.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/TMDBClientTests.swift`

- [ ] **Step 1: Write the failing tests**

Append inside the existing `extension MockTests { @Suite struct TMDBClientTests { … } }` in
`Packages/DebridCore/Tests/DebridCoreTests/TMDBClientTests.swift` (add these methods inside that
suite — they reuse its `MockURLProtocol.handler = nil` init):

```swift
        @Test func trendingWeekURLAndDecode() async throws {
            MockURLProtocol.handler = { req in
                #expect(req.url!.absoluteString.contains("trending/movie/week"))
                #expect(req.url!.absoluteString.contains("page=1"))
                let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(#"{"results":[{"id":1,"title":"M","vote_average":7.0}]}"#.utf8))
            }
            let client = TMDBClient(apiKey: "KEY", http: HTTPClient(session: .mock))
            let r = try await client.trendingMovies(window: .week)
            #expect(r.first?.id == 1)
        }

        @Test func curatedTopRatedURL() async throws {
            MockURLProtocol.handler = { req in
                #expect(req.url!.absoluteString.contains("movie/top_rated"))
                let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(#"{"results":[{"id":2,"title":"T"}]}"#.utf8))
            }
            let client = TMDBClient(apiKey: "KEY", http: HTTPClient(session: .mock))
            #expect(try await client.topRatedMoviesCurated().first?.id == 2)
        }

        @Test func recommendationsURL() async throws {
            MockURLProtocol.handler = { req in
                #expect(req.url!.absoluteString.contains("movie/603/recommendations"))
                let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(#"{"results":[{"id":5,"title":"R"}]}"#.utf8))
            }
            let client = TMDBClient(apiKey: "KEY", http: HTTPClient(session: .mock))
            #expect(try await client.recommendedMovies(id: 603).first?.id == 5)
        }

        @Test func decadeMoviesCarriesWindowAndFloor() async throws {
            MockURLProtocol.handler = { req in
                let u = req.url!.absoluteString
                #expect(u.contains("discover/movie"))
                #expect(u.contains("primary_release_date.gte=2010-01-01"))
                #expect(u.contains("primary_release_date.lte=2019-12-31"))
                #expect(u.contains("vote_count.gte=1000"))
                let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(#"{"results":[]}"#.utf8))
            }
            let client = TMDBClient(apiKey: "KEY", http: HTTPClient(session: .mock))
            _ = try await client.decadeMovies(from: "2010-01-01", to: "2019-12-31")
        }

        @Test func topRatedGenreUsesHardVoteFloor() async throws {
            MockURLProtocol.handler = { req in
                #expect(req.url!.absoluteString.contains("vote_count.gte=1500"))
                let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(#"{"results":[]}"#.utf8))
            }
            let client = TMDBClient(apiKey: "KEY", http: HTTPClient(session: .mock))
            _ = try await client.topRatedMovies(genreID: 28)
        }

        @Test func tvNewOverallURL() async throws {
            MockURLProtocol.handler = { req in
                #expect(req.url!.absoluteString.contains("discover/tv"))
                #expect(req.url!.absoluteString.contains("first_air_date.gte=2025-01-01"))
                let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(#"{"results":[{"id":9,"name":"S"}]}"#.utf8))
            }
            let client = TMDBClient(apiKey: "KEY", http: HTTPClient(session: .mock))
            #expect(try await client.discoverTVNew(firstAirFrom: "2025-01-01", firstAirTo: "2025-12-31").first?.id == 9)
        }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter TMDBClientTests`
Expected: FAIL — the new methods don't exist.

- [ ] **Step 3: Add the endpoints + page param + raise floors**

In `Packages/DebridCore/Sources/DebridCore/Metadata/TMDBClient.swift`:

First add the window enum at the top of the file, just under `import Foundation`:

```swift
/// TMDB trending window — `/trending/{kind}/{day|week}`.
public enum TMDBTrendingWindow: String, Sendable { case day, week }
```

Add a `page` query helper and the new methods. Insert these methods just **above** the
`private func get<T: Decodable>` at the bottom of the struct:

```swift
    // MARK: - Curated discovery (browse)

    private func pageItem(_ p: Int) -> URLQueryItem { URLQueryItem(name: "page", value: String(p)) }

    /// Real "what's hot" lists (not a discover sort).
    public func trendingMovies(window: TMDBTrendingWindow, page: Int = 1) async throws -> [TMDBSearchResult] {
        let r: TMDBSearchResponse = try await get("trending/movie/\(window.rawValue)", [pageItem(page)])
        return r.results
    }
    public func trendingTV(window: TMDBTrendingWindow, page: Int = 1) async throws -> [TMDBSearchResult] {
        let r: TMDBSearchResponse = try await get("trending/tv/\(window.rawValue)", [pageItem(page)])
        return r.results
    }

    /// TMDB's curated all-time top-rated lists.
    public func topRatedMoviesCurated(page: Int = 1) async throws -> [TMDBSearchResult] {
        let r: TMDBSearchResponse = try await get("movie/top_rated", [pageItem(page)])
        return r.results
    }
    public func topRatedTVCurated(page: Int = 1) async throws -> [TMDBSearchResult] {
        let r: TMDBSearchResponse = try await get("tv/top_rated", [pageItem(page)])
        return r.results
    }

    /// "More like this" for a title.
    public func recommendedMovies(id: Int, page: Int = 1) async throws -> [TMDBSearchResult] {
        let r: TMDBSearchResponse = try await get("movie/\(id)/recommendations", [pageItem(page)])
        return r.results
    }
    public func recommendedTV(id: Int, page: Int = 1) async throws -> [TMDBSearchResult] {
        let r: TMDBSearchResponse = try await get("tv/\(id)/recommendations", [pageItem(page)])
        return r.results
    }

    /// "Best of the decade" — date-windowed, highest-rated with a hard vote floor.
    public func decadeMovies(from: String, to: String, page: Int = 1) async throws -> [TMDBSearchResult] {
        let r: TMDBSearchResponse = try await get("discover/movie", [
            .init(name: "primary_release_date.gte", value: from),
            .init(name: "primary_release_date.lte", value: to),
            .init(name: "sort_by", value: "vote_average.desc"),
            .init(name: "vote_count.gte", value: "1000"),
            pageItem(page),
        ])
        return r.results
    }
    public func decadeTV(from: String, to: String, page: Int = 1) async throws -> [TMDBSearchResult] {
        let r: TMDBSearchResponse = try await get("discover/tv", [
            .init(name: "first_air_date.gte", value: from),
            .init(name: "first_air_date.lte", value: to),
            .init(name: "sort_by", value: "vote_average.desc"),
            .init(name: "vote_count.gte", value: "500"),
            pageItem(page),
        ])
        return r.results
    }

    /// New shows overall within a first-air-date window (the TV sibling of `discoverMovies(releaseFrom:releaseTo:)`).
    public func discoverTVNew(firstAirFrom: String, firstAirTo: String, page: Int = 1) async throws -> [TMDBSearchResult] {
        let r: TMDBSearchResponse = try await get("discover/tv", [
            .init(name: "first_air_date.gte", value: firstAirFrom),
            .init(name: "first_air_date.lte", value: firstAirTo),
            .init(name: "sort_by", value: "first_air_date.desc"),
            .init(name: "vote_count.gte", value: "30"),
            pageItem(page),
        ])
        return r.results
    }
```

Now **modify the existing genre methods** to add a `page` param and raise vote floors. Replace
each method body's query as follows (keep the doc comments):

- `discoverMovies(genreID:)` → add `page: Int = 1`, bump `vote_count.gte` `"100"` → `"200"`, append `pageItem(page)`.
- `discoverMovies(genreID:releaseFrom:releaseTo:)` → add `page: Int = 1`, bump `"10"` → `"30"`, append `pageItem(page)`.
- `topRatedMovies(genreID:)` → add `page: Int = 1`, bump `"300"` → `"1500"`, append `pageItem(page)`.
- `topRatedTV(genreID:)` → add `page: Int = 1`, bump `"200"` → `"800"`, append `pageItem(page)`.
- `discoverTV(genreID:firstAirFrom:firstAirTo:)` → add `page: Int = 1`, bump `"5"` → `"20"`, append `pageItem(page)`.
- `discoverTV(genreID:)` → add `page: Int = 1`, bump `"100"` → `"150"`, append `pageItem(page)`.
- `discoverMovies(releaseFrom:releaseTo:)` → add `page: Int = 1`, append `pageItem(page)` (keep floor `"50"`).

Example — the new `topRatedMovies(genreID:)`:

```swift
    public func topRatedMovies(genreID: Int, page: Int = 1) async throws -> [TMDBSearchResult] {
        let response: TMDBSearchResponse = try await get("discover/movie", [
            URLQueryItem(name: "with_genres", value: String(genreID)),
            URLQueryItem(name: "sort_by", value: "vote_average.desc"),
            URLQueryItem(name: "vote_count.gte", value: "1500"),
            pageItem(page),
        ])
        return response.results
    }
```

Apply the same shape (add `page` param + `pageItem(page)`, change the floor number) to the other six.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Packages/DebridCore --filter TMDBClientTests`
Expected: PASS (all existing + 6 new).

- [ ] **Step 5: Zero-warning + full brain suite**

Run: `swift build --package-path Packages/DebridCore 2>&1 | grep -i warning` (no output)
Run: `swift test --package-path Packages/DebridCore` (all green)

- [ ] **Step 6: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Metadata/TMDBClient.swift \
        Packages/DebridCore/Tests/DebridCoreTests/TMDBClientTests.swift
git commit -m "feat(core): TMDB trending/top-rated/recommendations/decade endpoints + paging + higher vote floors"
```

---

# SLICE 2 — DiscoverStore redesign

## Task 2: Rewrite DiscoverProviding + TMDBDiscoverService + DiscoverStore

**Files:**
- Rewrite: `Shared/DebridUI/Sources/DebridUI/Search/DiscoverStore.swift`
- Rewrite: `Shared/DebridUI/Tests/DebridUITests/DiscoverStoreTests.swift`

> This is one cohesive `@Observable` unit (protocol + service + store). We write the new test
> file first, watch it fail, then drop in the full new source file.

- [ ] **Step 1: Write the new test file**

Replace the entire contents of `Shared/DebridUI/Tests/DebridUITests/DiscoverStoreTests.swift`:

```swift
import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

/// Records which provider methods were called and returns canned results.
private final class FakeDiscover: DiscoverProviding, @unchecked Sendable {
    var result: [TMDBSearchResult] = [movie(1), movie(2)]
    var failGenres = false
    private(set) var calledTrending = false
    private(set) var calledTopRatedCurated = false
    private(set) var recommendedFor: [Int] = []

    func nowPlayingMovies() async throws -> [TMDBSearchResult] { [movie(7), movie(8)] }
    func trending(_ kind: MediaKind, window: TMDBTrendingWindow) async throws -> [TMDBSearchResult] {
        calledTrending = true; return result
    }
    func topRatedCurated(_ kind: MediaKind) async throws -> [TMDBSearchResult] {
        calledTopRatedCurated = true; return result
    }
    func newOverall(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] { result }
    func decade(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] { result }
    func recommended(_ kind: MediaKind, tmdbID: Int) async throws -> [TMDBSearchResult] {
        recommendedFor.append(tmdbID); return result
    }
    func newByGenre(_ kind: MediaKind, _ genreID: Int, from: String, to: String) async throws -> [TMDBSearchResult] {
        if failGenres { throw FakeError.boom }; return result
    }
    func popularByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult] {
        if failGenres { throw FakeError.boom }; return result
    }
    func topRatedByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult] {
        if failGenres { throw FakeError.boom }; return result
    }
}

private final class FakeSeeds: RecommendationSeedProviding, @unchecked Sendable {
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
        #expect(store.segmentState(.trending) == .idle)   // not loaded yet
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
        // 1 curated + 4 decade + one per genre
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
        #expect(store.segmentState(.popular) == .failed)   // zero rails → failed
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
        #expect(fake.recommendedFor == [100, 200])
    }

    @Test func forYouFallsBackToTrendingWhenNoSeeds() async {
        let fake = FakeDiscover()
        let store = DiscoverStore(kind: .movie, discover: fake, seeds: FakeSeeds())  // empty seeds
        await store.loadSegment(.forYou)
        let titles = (store.rowsBySegment[.forYou] ?? []).map(\.title)
        #expect(titles == ["Trending Today", "Trending This Week"])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Shared/DebridUI --filter DiscoverStoreTests`
Expected: FAIL — new API (`loadSegment`, `segmentState`, `movieGenreCount`, `seeds:`, `RecommendationSeed`) doesn't exist.

- [ ] **Step 3: Replace `DiscoverStore.swift` with the full new implementation**

Replace the entire contents of `Shared/DebridUI/Sources/DebridUI/Search/DiscoverStore.swift`:

```swift
import DebridCore
import Foundation
import Observation

/// Kind-parameterized browse data source. One conformance (`TMDBDiscoverService`) backs both the
/// Movies and TV tabs; the store passes its `kind` to each call.
public protocol DiscoverProviding: Sendable {
    func nowPlayingMovies() async throws -> [TMDBSearchResult]                                   // CAM set
    func trending(_ kind: MediaKind, window: TMDBTrendingWindow) async throws -> [TMDBSearchResult]
    func topRatedCurated(_ kind: MediaKind) async throws -> [TMDBSearchResult]
    func newOverall(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult]
    func decade(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult]
    func recommended(_ kind: MediaKind, tmdbID: Int) async throws -> [TMDBSearchResult]
    func newByGenre(_ kind: MediaKind, _ genreID: Int, from: String, to: String) async throws -> [TMDBSearchResult]
    func popularByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult]
    func topRatedByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult]
}

/// Production conformance. Fetches **2 pages per rail** (≈40 titles) and concatenates.
public struct TMDBDiscoverService: DiscoverProviding {
    let client: TMDBClient
    public init(client: TMDBClient) { self.client = client }
    private static let pages = 2

    private func paged(_ f: (Int) async throws -> [TMDBSearchResult]) async rethrows -> [TMDBSearchResult] {
        var all: [TMDBSearchResult] = []
        for p in 1...Self.pages { all += try await f(p) }
        return all
    }

    public func nowPlayingMovies() async throws -> [TMDBSearchResult] { try await client.nowPlayingMovies() }

    public func trending(_ kind: MediaKind, window: TMDBTrendingWindow) async throws -> [TMDBSearchResult] {
        try await paged { p in kind == .movie ? try await client.trendingMovies(window: window, page: p)
                                              : try await client.trendingTV(window: window, page: p) }
    }
    public func topRatedCurated(_ kind: MediaKind) async throws -> [TMDBSearchResult] {
        try await paged { p in kind == .movie ? try await client.topRatedMoviesCurated(page: p)
                                              : try await client.topRatedTVCurated(page: p) }
    }
    public func newOverall(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] {
        try await paged { p in kind == .movie ? try await client.discoverMovies(releaseFrom: from, releaseTo: to, page: p)
                                              : try await client.discoverTVNew(firstAirFrom: from, firstAirTo: to, page: p) }
    }
    public func decade(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] {
        try await paged { p in kind == .movie ? try await client.decadeMovies(from: from, to: to, page: p)
                                              : try await client.decadeTV(from: from, to: to, page: p) }
    }
    public func recommended(_ kind: MediaKind, tmdbID: Int) async throws -> [TMDBSearchResult] {
        kind == .movie ? try await client.recommendedMovies(id: tmdbID) : try await client.recommendedTV(id: tmdbID)
    }
    public func newByGenre(_ kind: MediaKind, _ genreID: Int, from: String, to: String) async throws -> [TMDBSearchResult] {
        try await paged { p in kind == .movie ? try await client.discoverMovies(genreID: genreID, releaseFrom: from, releaseTo: to, page: p)
                                              : try await client.discoverTV(genreID: genreID, firstAirFrom: from, firstAirTo: to, page: p) }
    }
    public func popularByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult] {
        try await paged { p in kind == .movie ? try await client.discoverMovies(genreID: genreID, page: p)
                                              : try await client.discoverTV(genreID: genreID, page: p) }
    }
    public func topRatedByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult] {
        try await paged { p in kind == .movie ? try await client.topRatedMovies(genreID: genreID, page: p)
                                              : try await client.topRatedTV(genreID: genreID, page: p) }
    }
}

/// Kind-aware browse content across 5 segments, each a stack of horizontal rails. Segments load
/// **lazily** (the first time they're shown) and are cached for the session. Per-rail failures
/// are dropped; a segment with zero successful rails is `.failed`.
@MainActor
@Observable
public final class DiscoverStore {
    public enum Segment: String, CaseIterable, Identifiable, Sendable {
        case forYou = "For You", trending = "Trending", newReleases = "New",
             popular = "Popular", topRated = "Top Rated"
        public var id: String { rawValue }
        public var title: String { rawValue }
    }
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let hits: [SearchHit]
    }
    public enum State: Equatable { case idle, loading, loaded, failed }

    public var selectedSegment: Segment = .forYou
    public private(set) var rowsBySegment: [Segment: [Row]] = [:]
    private var states: [Segment: State] = [:]
    public private(set) var camIDs: Set<Int> = []

    public let kind: MediaKind
    private let discover: DiscoverProviding
    private let seeds: RecommendationSeedProviding?
    private let now: @Sendable () -> Date

    /// Selected-segment state, so existing view code can read one `state`.
    public var state: State { states[selectedSegment] ?? .idle }
    public func segmentState(_ s: Segment) -> State { states[s] ?? .idle }
    public var rows: [Row] { rowsBySegment[selectedSegment] ?? [] }
    public func isCAM(_ result: TMDBSearchResult) -> Bool { camIDs.contains(result.id) }
    public func select(_ segment: Segment) { selectedSegment = segment }

    // Genre tables (id, display name). Movie and TV genre ids differ.
    static let movieGenres: [(String, Int)] = [
        ("Action", 28), ("Adventure", 12), ("Animation", 16), ("Comedy", 35), ("Crime", 80),
        ("Documentary", 99), ("Drama", 18), ("Family", 10751), ("Fantasy", 14), ("History", 36),
        ("Horror", 27), ("Music", 10402), ("Mystery", 9648), ("Romance", 10749),
        ("Sci-Fi", 878), ("Thriller", 53), ("War", 10752), ("Western", 37),
    ]
    static let tvGenres: [(String, Int)] = [
        ("Action & Adventure", 10759), ("Animation", 16), ("Comedy", 35), ("Crime", 80),
        ("Documentary", 99), ("Drama", 18), ("Family", 10751), ("Kids", 10762),
        ("Mystery", 9648), ("Reality", 10764), ("Sci-Fi & Fantasy", 10765),
        ("War & Politics", 10768), ("Western", 37),
    ]
    /// Decade rails (label, fromYear, toYear).
    static let decades: [(String, Int, Int)] = [
        ("Best of the 2020s", 2020, 2029), ("Best of the 2010s", 2010, 2019),
        ("Best of the 2000s", 2000, 2009), ("Best of the 90s", 1990, 1999),
    ]
    public static var movieGenreCount: Int { movieGenres.count }
    public static var tvGenreCount: Int { tvGenres.count }
    public static var decadeCount: Int { decades.count }

    private var genres: [(String, Int)] { kind == .movie ? Self.movieGenres : Self.tvGenres }

    public init(kind: MediaKind, discover: DiscoverProviding,
                seeds: RecommendationSeedProviding? = nil,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.kind = kind; self.discover = discover; self.seeds = seeds; self.now = now
    }

    /// Back-compat: load the currently-selected segment.
    public func load() async { await loadSegment(selectedSegment) }

    /// Load one segment's rails if not already loaded/loading. Idempotent.
    public func loadSegment(_ segment: Segment) async {
        switch states[segment] ?? .idle {
        case .loading, .loaded: return
        case .idle, .failed: break
        }
        states[segment] = .loading
        if kind == .movie && camIDs.isEmpty {
            camIDs = Set(((try? await discover.nowPlayingMovies()) ?? []).map(\.id))
        }
        let specs = await rowSpecs(for: segment)
        let built = await runCapped(specs)
        rowsBySegment[segment] = built
        states[segment] = built.isEmpty ? .failed : .loaded
    }

    // MARK: - Row specs per segment

    private struct RowSpec {
        let id: String
        let title: String
        let fetch: @Sendable () async -> [TMDBSearchResult]
    }

    private func rowSpecs(for segment: Segment) async -> [RowSpec] {
        switch segment {
        case .forYou:      return await forYouSpecs()
        case .trending:    return trendingSpecs()
        case .newReleases: return newSpecs()
        case .popular:     return popularSpecs()
        case .topRated:    return topRatedSpecs()
        }
    }

    private func trendingSpecs() -> [RowSpec] {
        let d = discover, k = kind
        return [
            RowSpec(id: "trend-day", title: "Trending Today",
                    fetch: { (try? await d.trending(k, window: .day)) ?? [] }),
            RowSpec(id: "trend-week", title: "Trending This Week",
                    fetch: { (try? await d.trending(k, window: .week)) ?? [] }),
        ]
    }

    private func newSpecs() -> [RowSpec] {
        let d = discover, k = kind
        let (from, to) = releaseWindow()
        var specs = [RowSpec(id: "new-all", title: "New This Month",
                             fetch: { (try? await d.newOverall(k, from: from, to: to)) ?? [] })]
        for (name, gid) in genres {
            specs.append(RowSpec(id: "new-\(gid)", title: "New in \(name)",
                                 fetch: { (try? await d.newByGenre(k, gid, from: from, to: to)) ?? [] }))
        }
        return specs
    }

    private func popularSpecs() -> [RowSpec] {
        let d = discover, k = kind
        return genres.map { (name, gid) in
            RowSpec(id: "pop-\(gid)", title: "Popular in \(name)",
                    fetch: { (try? await d.popularByGenre(k, gid)) ?? [] })
        }
    }

    private func topRatedSpecs() -> [RowSpec] {
        let d = discover, k = kind
        var specs = [RowSpec(id: "top-curated", title: "Top Rated of All Time",
                             fetch: { (try? await d.topRatedCurated(k)) ?? [] })]
        for (label, from, to) in Self.decades {
            let f = "\(from)-01-01", t = "\(to)-12-31"
            specs.append(RowSpec(id: "decade-\(from)", title: label,
                                 fetch: { (try? await d.decade(k, from: f, to: t)) ?? [] }))
        }
        for (name, gid) in genres {
            specs.append(RowSpec(id: "topg-\(gid)", title: "Top \(name)",
                                 fetch: { (try? await d.topRatedByGenre(k, gid)) ?? [] }))
        }
        return specs
    }

    private func forYouSpecs() async -> [RowSpec] {
        let d = discover, k = kind
        let seedList = await seeds?.seeds(kind: kind, limit: 10) ?? []
        guard !seedList.isEmpty else { return trendingSpecs() }   // fallback: never blank
        return seedList.map { seed in
            let title = seed.watched ? "Because you watched \(seed.title)" : "More like \(seed.title)"
            return RowSpec(id: "rec-\(seed.tmdbID)", title: title,
                           fetch: { (try? await d.recommended(k, tmdbID: seed.tmdbID)) ?? [] })
        }
    }

    // MARK: - Concurrency-capped fetch

    /// Runs the row fetches with at most `cap` in flight, preserving spec order, dropping empties.
    private func runCapped(_ specs: [RowSpec], cap: Int = 8) async -> [Row] {
        let kind = self.kind
        let indexed: [(Int, [SearchHit])] = await withTaskGroup(of: (Int, [SearchHit]).self) { group in
            var next = 0, running = 0
            var out: [(Int, [SearchHit])] = []
            func addTask(_ i: Int) {
                let spec = specs[i]
                group.addTask { (i, (await spec.fetch()).map { SearchHit(result: $0, kind: kind) }) }
            }
            while next < specs.count && running < cap { addTask(next); next += 1; running += 1 }
            for await pair in group {
                out.append(pair)
                if next < specs.count { addTask(next); next += 1 } else { running -= 1 }
            }
            return out
        }
        let byIndex = Dictionary(uniqueKeysWithValues: indexed)
        // Dedup poster ids ACROSS rails in this segment so the same title doesn't repeat everywhere.
        var seen = Set<Int>()
        var rows: [Row] = []
        for i in specs.indices {
            let hits = (byIndex[i] ?? []).filter { seen.insert($0.result.id).inserted }
            if hits.isEmpty { continue }
            rows.append(Row(id: specs[i].id, title: specs[i].title, hits: hits))
        }
        return rows
    }

    /// "New" window: released between ~10 months and ~1.5 months ago.
    private func releaseWindow() -> (from: String, to: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = now()
        let from = cal.date(byAdding: .day, value: -300, to: today) ?? today
        let to = cal.date(byAdding: .day, value: -45, to: today) ?? today
        return (Self.iso.string(from: from), Self.iso.string(from: to))
    }

    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
```

> Note the dedup in `runCapped` drops a title from a later rail if it already appeared in an
> earlier rail of the same segment. For the `failedGenreRailsAreDropped` test, all fetches return
> `[]` (the `try?` swallows the throw) → every rail empty → `rows` empty → `.failed`. ✓
> For `popularHasOneRailPerMovieGenre`, each genre returns `[movie(1),movie(2)]` but dedup means
> only the FIRST genre rail keeps both and the rest would be empty → **the count assertion would
> fail**. To keep per-genre rails distinct in tests, the `FakeDiscover` must return **unique ids
> per call**. Update the fake's genre methods before running:

Adjust `FakeDiscover` in the test file so each genre call yields unique ids — replace the three
`*ByGenre` methods with counter-based results:

```swift
    private var genreCounter = 0
    func newByGenre(_ kind: MediaKind, _ genreID: Int, from: String, to: String) async throws -> [TMDBSearchResult] {
        if failGenres { throw FakeError.boom }; genreCounter += 1; return [movie(1000 + genreCounter)]
    }
    func popularByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult] {
        if failGenres { throw FakeError.boom }; genreCounter += 1; return [movie(2000 + genreCounter)]
    }
    func topRatedByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult] {
        if failGenres { throw FakeError.boom }; genreCounter += 1; return [movie(3000 + genreCounter)]
    }
```

(Also make `decade`/`topRatedCurated`/`newOverall`/`trending` return unique ids so the Top-Rated
count test isn't reduced by dedup — return `[movie(4000 + Int.random...)]`? No — random is banned.
Instead give each a fixed unique id: `trending` → `[movie(9001)]`/`[movie(9002)]` by window,
`topRatedCurated` → `[movie(9100)]`, `newOverall` → `[movie(9200)]`, `decade` → counter `5000+`.)
Update those fake methods to return unique fixed ids accordingly.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Shared/DebridUI --filter DiscoverStoreTests`
Expected: PASS.

- [ ] **Step 5: Zero-warning check**

Run: `swift build --package-path Shared/DebridUI 2>&1 | grep -i warning`
Expected: no output. (If `RecommendationSeedProviding`/`RecommendationSeed` are undefined, that's
expected until Task 3 — but they're referenced here, so define a minimal stub now: create the file
in Task 3 BEFORE building. Reorder: do Task 3 Step 1-3 source, then build. To keep this task green
on its own, add the seam definition as Step 5a below.)

- [ ] **Step 5a: Add the seam definitions referenced above**

Create `Shared/DebridUI/Sources/DebridUI/Search/RecommendationSeedProviding.swift`:

```swift
import DebridCore

/// One title to seed "For You" recommendations from.
public struct RecommendationSeed: Sendable, Equatable {
    public let tmdbID: Int
    public let title: String
    public let watched: Bool
    public init(tmdbID: Int, title: String, watched: Bool) {
        self.tmdbID = tmdbID; self.title = title; self.watched = watched
    }
}

/// Vends seed titles for "For You" — watched-first, then library. `@MainActor` because the
/// production conformance reads the main-actor `LibraryStore`.
@MainActor
public protocol RecommendationSeedProviding: AnyObject, Sendable {
    func seeds(kind: MediaKind, limit: Int) async -> [RecommendationSeed]
}
```

Re-run Step 4 + Step 5.

- [ ] **Step 6: Full DebridUI suite (existing tests must still pass)**

Run: `swift test --package-path Shared/DebridUI`
Expected: all green. (BrowseScreen isn't compiled by `swift test`; the apps are updated in Slice 4.)

- [ ] **Step 7: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Search/DiscoverStore.swift \
        Shared/DebridUI/Sources/DebridUI/Search/RecommendationSeedProviding.swift \
        Shared/DebridUI/Tests/DebridUITests/DiscoverStoreTests.swift
git commit -m "feat(ui): DiscoverStore — 5 lazy segments, all genres, curated + decade + For-You rails"
```

---

# SLICE 3 — For You recommendations wiring

## Task 3: RecommendationSeedService + AppSession wiring

**Files:**
- Modify: `Shared/DebridUI/Sources/DebridUI/Search/RecommendationSeedProviding.swift`
- Modify: `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift`
- Test: `Shared/DebridUI/Tests/DebridUITests/RecommendationSeedServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Shared/DebridUI/Tests/DebridUITests/RecommendationSeedServiceTests.swift`:

```swift
import Testing
import Foundation
import DebridCore
@testable import DebridUI

@MainActor
struct RecommendationSeedServiceTests {
    private func item(_ id: Int, key: String) -> MediaItem {
        MediaItem(id: key, kind: .movie, title: "T\(id)", year: 2020, sources: [], seasons: [],
                  tmdbID: id, overview: nil)
    }
    // Watch fake returning canned recently-watched states.
    final class FakeWatch: WatchProgressProviding, @unchecked Sendable {
        var states: [WatchState] = []
        func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { nil }
        func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                    durationSeconds: Double, finished: Bool, profileID: String) async throws {}
        func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { states }
        func deleteProgress(forContentKeys keys: [String]) async throws {}
    }

    @Test func watchedSeedsComeFirstThenLibrary() async {
        let lib = LibraryStore(library: NoopLibrary(), watch: nil)
        lib.setForTest(movies: [item(1, key: "movie:tmdb:1"), item(2, key: "movie:tmdb:2")], shows: [])
        let watch = FakeWatch()
        watch.states = [WatchState(contentKey: "movie:tmdb:2", sourceKey: "s", positionSeconds: 10,
                                   durationSeconds: 100, finished: false)]
        let svc = RecommendationSeedService(watch: watch, library: lib, profileID: { "p1" })
        let seeds = await svc.seeds(kind: .movie, limit: 10)
        #expect(seeds.first == RecommendationSeed(tmdbID: 2, title: "T2", watched: true))
        #expect(seeds.contains(RecommendationSeed(tmdbID: 1, title: "T1", watched: false)))
        #expect(seeds.count == 2)   // no dup of tmdb 2
    }

    @Test func respectsLimit() async {
        let lib = LibraryStore(library: NoopLibrary(), watch: nil)
        lib.setForTest(movies: (1...5).map { item($0, key: "movie:tmdb:\($0)") }, shows: [])
        let svc = RecommendationSeedService(watch: FakeWatch(), library: lib, profileID: { "p1" })
        #expect(await svc.seeds(kind: .movie, limit: 3).count == 3)
    }
}

private struct NoopLibrary: LibraryProviding {
    func loadCached() -> ([MediaItem], [MediaItem])? { nil }
    func refresh() async throws -> ([MediaItem], [MediaItem]) { ([], []) }
    func remove(_ item: MediaItem) async throws {}
    func removeVersion(_ item: MediaItem, source: MediaSource) async throws {}
}
```

> The test needs a way to set `LibraryStore.movies/shows` directly. Add a tiny test-only helper.
> Confirm the `WatchState` and `LibraryProviding` initializers/method names against the codebase
> when implementing (`WatchState` field order, `LibraryProviding` requirements) and adjust the
> fakes to match — the test only needs: a library exposing two movies and a watch returning one
> state whose `contentKey` matches a movie's `id`.

- [ ] **Step 2: Add the `setForTest` helper to LibraryStore**

In `Shared/DebridUI/Sources/DebridUI/Library/LibraryStore.swift`, add (anywhere in the class):

```swift
    #if DEBUG
    /// Test-only: seed the split arrays without a network/library round-trip.
    func setForTest(movies: [MediaItem], shows: [MediaItem]) { self.movies = movies; self.shows = shows }
    #endif
```

- [ ] **Step 3: Run to verify it fails**

Run: `swift test --package-path Shared/DebridUI --filter RecommendationSeedServiceTests`
Expected: FAIL — `RecommendationSeedService` doesn't exist.

- [ ] **Step 4: Implement the service**

Append to `Shared/DebridUI/Sources/DebridUI/Search/RecommendationSeedProviding.swift`:

```swift

/// Production seeds: watched titles (most-recent first), then library titles, deduped by TMDB id.
@MainActor
public final class RecommendationSeedService: RecommendationSeedProviding {
    private let watch: WatchProgressProviding
    private weak var library: LibraryStore?
    private let profileID: @MainActor () -> String?

    public init(watch: WatchProgressProviding, library: LibraryStore?,
                profileID: @escaping @MainActor () -> String?) {
        self.watch = watch; self.library = library; self.profileID = profileID
    }

    public func seeds(kind: MediaKind, limit: Int) async -> [RecommendationSeed] {
        guard let library else { return [] }
        let items = kind == .movie ? library.movies : library.shows
        var out: [RecommendationSeed] = []
        var seen = Set<Int>()

        if let pid = profileID() {
            let states = (try? await watch.recentlyWatched(limit: 30, profileID: pid)) ?? []
            for s in states {
                guard let item = Self.resolve(s.contentKey, in: items),
                      let tmdb = item.tmdbID, seen.insert(tmdb).inserted else { continue }
                out.append(.init(tmdbID: tmdb, title: item.title, watched: true))
                if out.count >= limit { return out }
            }
        }
        for item in items {
            guard let tmdb = item.tmdbID, seen.insert(tmdb).inserted else { continue }
            out.append(.init(tmdbID: tmdb, title: item.title, watched: false))
            if out.count >= limit { break }
        }
        return out
    }

    /// Movie content keys equal the item id; episode keys are `showID:sXeY`.
    static func resolve(_ contentKey: String, in items: [MediaItem]) -> MediaItem? {
        items.first { $0.id == contentKey } ?? items.first { contentKey.hasPrefix($0.id + ":") }
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --package-path Shared/DebridUI --filter RecommendationSeedServiceTests`
Expected: PASS.

- [ ] **Step 6: Wire into AppSession**

In `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift`, find the discover wiring (the
`let discover = TMDBDiscoverService(client: tmdb)` / `moviesBrowse = …` / `showsBrowse = …` block,
~line 295) and replace those three lines with:

```swift
        let discover = TMDBDiscoverService(client: tmdb)
        let seedService = RecommendationSeedService(
            watch: watchStore ?? NoWatch(), library: libraryStore,
            profileID: { [weak self] in self?.activeProfileID })
        moviesBrowse = DiscoverStore(kind: .movie, discover: discover, seeds: seedService)
        showsBrowse = DiscoverStore(kind: .show, discover: discover, seeds: seedService)
```

`watchStore` may be nil (no SwiftData). Add a tiny no-op `WatchProgressProviding` near the bottom
of `AppSession.swift` (after the class, file scope):

```swift
/// No-op watch store for when SwiftData is unavailable — seeds then come from the library only.
private struct NoWatch: WatchProgressProviding {
    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { nil }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws {}
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
    func deleteProgress(forContentKeys keys: [String]) async throws {}
}
```

> Confirm `WatchProgressProviding`'s exact requirements at
> `Shared/DebridUI/Sources/DebridUI/Detail/WatchProgressProviding.swift` and match `NoWatch` to
> them (the seam shown here is current as of this plan).

- [ ] **Step 7: Build + full suite**

Run: `swift build --package-path Shared/DebridUI 2>&1 | grep -i warning` (no output)
Run: `swift test --package-path Shared/DebridUI` (all green)

- [ ] **Step 8: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Search/RecommendationSeedProviding.swift \
        Shared/DebridUI/Sources/DebridUI/Library/LibraryStore.swift \
        Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift \
        Shared/DebridUI/Tests/DebridUITests/RecommendationSeedServiceTests.swift
git commit -m "feat(ui): For-You seed service (watched-first, then library) wired into browse"
```

---

# SLICE 4 — Apps: lazy per-segment browse

## Task 4: SeretTV BrowseScreen — always-visible picker + lazy segment load

**Files:**
- Modify: `Apps/SeretTV/Browse/BrowseScreen.swift`

- [ ] **Step 1: Replace the `rows` computed view + segment trigger**

In `Apps/SeretTV/Browse/BrowseScreen.swift`, replace the entire `@ViewBuilder private var rows: some View { … }` (the block that switches on `browse.state` and renders the segment picker inside `.loaded`) with a version where the **picker is always visible** and only the rail area reacts to the selected segment's state:

```swift
    @ViewBuilder private var rows: some View {
        if let browse {
            VStack(alignment: .leading, spacing: 0) {
                segmentPicker(browse).padding(.leading, 60).padding(.bottom, 8)
                segmentContent(browse)
            }
            // Load the selected segment whenever it changes (and on first show). Lazy + cached.
            .task(id: browse.selectedSegment) { await browse.loadSegment(browse.selectedSegment) }
        }
    }

    @ViewBuilder private func segmentContent(_ browse: DiscoverStore) -> some View {
        switch browse.segmentState(browse.selectedSegment) {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 54)).foregroundStyle(.secondary)
                Text("Couldn't load.").font(.title3)
                Button("Retry") { Task { await browse.loadSegment(browse.selectedSegment) } }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 40) {
                    ForEach(browse.rows) { row in
                        rail(title: row.title, hits: row.hits, cam: false)
                    }
                }
                .padding(.vertical, 20)
            }
        }
    }
```

> The retry case calls `loadSegment` again; since the segment is `.failed` (not `.loaded`),
> `loadSegment`'s guard lets it re-run. The `segmentPicker(_:)` and `rail(...)` helpers already
> exist and are unchanged. The picker's `onChange(focusedSegment)` already calls `browse.select`,
> which flips `selectedSegment`, which re-fires the `.task(id:)` → loads the new segment.

- [ ] **Step 2: Build SeretTV**

Run:
```bash
cd /Users/shaharsolomons/Documents/Code/Seret && xcodegen generate && \
xcodebuild -scheme SeretTV -destination 'generic/platform=tvOS Simulator' build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:" | head
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Apps/SeretTV/Browse/BrowseScreen.swift
git commit -m "feat(tv): lazy per-segment browse with always-visible 5-segment picker"
```

---

## Task 5: SeretMobile BrowseScreen — always-visible picker + lazy segment load

**Files:**
- Modify: `Apps/SeretMobile/Browse/BrowseScreen.swift`

- [ ] **Step 1: Replace the `rails` computed view + segment trigger**

In `Apps/SeretMobile/Browse/BrowseScreen.swift`, replace the entire `private var rails: some View { … }` with a version where the picker is always visible and the rail area reacts to the selected segment's state:

```swift
    private var rails: some View {
        Group {
            if let browse {
                VStack(spacing: Theme.Space.md) {
                    segmentPicker(browse)
                    segmentContent(browse)
                }
                .task(id: browse.selectedSegment) { await browse.loadSegment(browse.selectedSegment) }
            }
        }
    }

    @ViewBuilder private func segmentContent(_ browse: DiscoverStore) -> some View {
        switch browse.segmentState(browse.selectedSegment) {
        case .idle, .loading:
            loadingView
        case .failed:
            message("Couldn't load \(title.lowercased())", systemImage: "exclamationmark.triangle")
        case .loaded:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.lg) {
                    ForEach(browse.rows) { row in
                        Rail(title: row.title) {
                            ForEach(row.hits) { tile($0, width: 120, cam: isCAM($0)) }
                        }
                    }
                }
                .padding(.vertical, Theme.Space.md)
            }
        }
    }
```

> The mobile `segmentPicker(_:)` is a `.segmented` `Picker` bound to `browse.selectedSegment` via
> `browse.select`. Changing the segment flips `selectedSegment` → the `.task(id:)` re-fires →
> loads that segment. `Rail`, `tile`, `isCAM`, `loadingView`, `message` already exist. The five
> segments come from `DiscoverStore.Segment.allCases` automatically; the segmented control will
> show all five (For You · Trending · New · Popular · Top Rated).

- [ ] **Step 2: Build SeretMobile**

Run:
```bash
cd /Users/shaharsolomons/Documents/Code/Seret && xcodegen generate && \
xcodebuild -scheme SeretMobile -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:" | head
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Apps/SeretMobile/Browse/BrowseScreen.swift
git commit -m "feat(mobile): lazy per-segment browse with always-visible 5-segment picker"
```

---

## Task 6: Full verification

- [ ] **Step 1: Full brain + UI suites**

Run: `swift test --package-path Packages/DebridCore` (all green)
Run: `swift test --package-path Shared/DebridUI` (all green)

- [ ] **Step 2: Zero-warning check**

Run:
```bash
swift build --package-path Packages/DebridCore 2>&1 | grep -i warning
swift build --package-path Shared/DebridUI 2>&1 | grep -i warning
```
Expected: no output.

- [ ] **Step 3: Build both apps**

Run:
```bash
cd /Users/shaharsolomons/Documents/Code/Seret && xcodegen generate
xcodebuild -scheme SeretMobile -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -2
xcodebuild -scheme SeretTV    -destination 'generic/platform=tvOS Simulator' build 2>&1 | tail -2
```
Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 4: Owner-pending — sim verification**

This env can't launch the sim. The owner verifies in the simulator (signed in with the RD token):
open Movies → see the 5-segment picker; For You shows "Because you watched…" / "More like…" rails
(or Trending if nothing watched yet); Top Rated shows recognizable canon (Shawshank/Godfather) +
decade rails; every genre has a rail; switching segments loads quickly and stays cached.

---

## Self-Review Notes

- **Spec coverage:** 5 enriched segments (T2), all genres (T2 genre tables), more-per-rail = 2
  pages (T2 `TMDBDiscoverService.paged`), real trending + curated top-rated + decade endpoints
  (T1), recommendations seeded watched-first→library (T3), lazy per-segment load (T2/T4/T5),
  mainstream-global = high vote floors + no language filter (T1). ✓ Trending refined to 2 curated
  rails (noted up top) to avoid duplicating Popular's per-genre popularity rows.
- **Type consistency:** `DiscoverProviding` (kind-parameterized) used identically in the service,
  store, and fake. `RecommendationSeed`/`RecommendationSeedProviding`/`RecommendationSeedService`
  consistent across T2/T3. `loadSegment`/`segmentState`/`rowsBySegment`/`Segment` consistent across
  store + both apps. `TMDBTrendingWindow` defined in T1, used in T2.
- **Watch-outs flagged inline:** (1) verify `WatchProgressProviding`, `WatchState`,
  `LibraryProviding`, `MediaItem`, `SearchHit`, `TMDBSearchResult` initializers against the live
  code when writing fakes — match them. (2) `FakeDiscover` must return unique ids per call so the
  segment dedup doesn't shrink rail counts in tests (spelled out in T2 Step 3). (3) `swift test`
  doesn't compile the apps — Slice 4 builds them. (4) Stage only listed paths (parallel WIP on
  `feat/profiles`).
