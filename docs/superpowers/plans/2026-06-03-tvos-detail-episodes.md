# Seret tvOS — Library Drill-Down: Detail + Episodes (Plan 7b-ii) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make library posters open a Detail screen — backdrop-forward hero, Play/Resume, quality chips and Versions for movies; season picker + vertical episode list with watch-progress for shows — handing playback to a placeholder that Plan 7c will replace.

**Architecture:** Three small pure additions to the `DebridCore` brain (`Hashable` for value-based nav, a source-quality ranker, a TMDB season-episodes endpoint), then the tvOS UI: a `@MainActor @Observable DetailStore` (TDD'd against fakes, mirroring 7b-i's `LibraryStore`) feeding `MovieDetailView` / `ShowDetailView` reached via a `NavigationStack`. Rich metadata is fetched on-demand from TMDB and cached for the session; the saved library snapshot is untouched.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI (tvOS 18), Swift Testing, SwiftData (`WatchProgressStore`, via a Sendable seam), XcodeGen.

**Spec:** [`docs/superpowers/specs/2026-06-03-tvos-detail-episodes-design.md`](../specs/2026-06-03-tvos-detail-episodes-design.md)

Run all commands from the repo root (`/Users/shaharsolomons/Documents/Code/Seret`).

---

## File Structure

**Create (brain — `Packages/DebridCore/Sources/DebridCore/`):**
- `Library/MediaSourceRanking.swift` — pure `MediaSource.qualityRank` + `[MediaSource].bestFirst()`/`.best`.

**Modify (brain):**
- `Library/MediaItem.swift` — add `Hashable` to `MediaKind`/`MediaSource`/`Episode`/`Season`/`MediaItem`.
- `Metadata/ParsedRelease.swift` — add `Hashable`.
- `Metadata/TMDBModels.swift` — add `TMDBSeasonDetails` + `TMDBEpisodeDetails`; add public memberwise inits to `TMDBGenre`/`TMDBMovieDetails`/`TMDBTVDetails`.
- `Metadata/TMDBClient.swift` — add `tvSeasonDetails(tvID:season:)`.

**Create (app — `Apps/SeretTV/`):**
- `Detail/MediaDetailsProviding.swift` — seam protocol + `TMDBDetailsService`.
- `Detail/WatchProgressProviding.swift` — seam protocol + `WatchProgressStore` conformance.
- `Detail/DetailStore.swift` — the observable store.
- `Detail/DetailView.swift` — routes movie/show, owns the store.
- `Detail/MovieDetailView.swift`, `Detail/ShowDetailView.swift`, `Detail/EpisodeRow.swift`, `Detail/QualityChips.swift`, `Detail/BackdropBackground.swift`.
- `Playback/PlaybackRequest.swift`, `Playback/PlayerPlaceholderView.swift`.

**Modify (app):**
- `Shell/AppSession.swift` — vend `detailsProvider` + `watchStore` on sign-in.
- `Shell/LibraryShell.swift` — wrap grids in a `NavigationStack` + `navigationDestination`.
- `Library/PosterCard.swift` — `Button` → `NavigationLink(value:)`.

**Create (tests):**
- `Packages/.../Tests/DebridCoreTests/DomainHashableTests.swift`, `MediaSourceRankingTests.swift`.
- `Apps/SeretTVTests/DetailStoreTests.swift`.

**Modify (tests):**
- `Packages/.../Tests/DebridCoreTests/TMDBClientTests.swift` — add a `tvSeasonDetails` decode test.

**Commit convention:** brain → `feat(core):`/`test(core):`; app → `feat(tvos):`. Every commit ends with the `Co-Authored-By` trailer shown in the steps.

---

## Task 1: Brain — `Hashable` for value-based navigation

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Library/MediaItem.swift`
- Modify: `Packages/DebridCore/Sources/DebridCore/Metadata/ParsedRelease.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/DomainHashableTests.swift` (create)

- [ ] **Step 1: Write the failing test** — create `DomainHashableTests.swift`:

```swift
import Testing
import DebridCore

@Suite struct DomainHashableTests {
    @Test func mediaItemUsableAsNavigationValue() {
        let s = MediaSource(torrentID: "t", fileID: 1, restrictedLink: "l",
                            parsed: ParsedRelease(title: "x", resolution: "1080p"))
        let a = MediaItem(id: "1", kind: .movie, title: "A", year: 2024, sources: [s], seasons: [])
        let b = MediaItem(id: "1", kind: .movie, title: "A", year: 2024, sources: [s], seasons: [])
        let c = MediaItem(id: "2", kind: .movie, title: "B", year: 2024, sources: [], seasons: [])
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)        // equal values hash equal
        var set: Set<MediaItem> = [a]
        #expect(set.contains(b))
        set.insert(c)
        #expect(set.count == 2)
    }

    @Test func episodeAndSeasonHashable() {
        let ep = Episode(season: 1, number: 1,
                         source: MediaSource(torrentID: "t", fileID: nil, restrictedLink: "l",
                                             parsed: ParsedRelease(title: "x")))
        let season = Season(number: 1, episodes: [ep])
        #expect(Set([ep]).contains(ep))
        #expect(Set([season]).contains(season))
    }
}
```

- [ ] **Step 2: Run it to confirm it fails (won't compile — types aren't `Hashable`)**

Run: `swift test --package-path Packages/DebridCore --filter DomainHashableTests`
Expected: FAIL — `type 'MediaItem' does not conform to protocol 'Hashable'` (or `Set<MediaItem>` error).

- [ ] **Step 3: Add `Hashable` conformances.** In `Metadata/ParsedRelease.swift` line 2, change the declaration:

```swift
public struct ParsedRelease: Sendable, Equatable, Hashable, Codable {
```

In `Library/MediaItem.swift`, add `Hashable` to all five type declarations (lines 3, 9, 23, 37, 51):

```swift
public enum MediaKind: String, Sendable, Equatable, Hashable, Codable {
```
```swift
public struct MediaSource: Sendable, Equatable, Hashable, Codable {
```
```swift
public struct Episode: Sendable, Equatable, Hashable, Identifiable, Codable {
```
```swift
public struct Season: Sendable, Equatable, Hashable, Identifiable, Codable {
```
```swift
public struct MediaItem: Sendable, Equatable, Hashable, Identifiable, Codable {
```

(All stored properties are already `Hashable`, so the synthesized conformance compiles with no other change.)

- [ ] **Step 4: Run the test to confirm it passes**

Run: `swift test --package-path Packages/DebridCore --filter DomainHashableTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Confirm zero warnings**

Run: `swift build --package-path Packages/DebridCore 2>&1 | grep -i warning`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Library/MediaItem.swift \
        Packages/DebridCore/Sources/DebridCore/Metadata/ParsedRelease.swift \
        Packages/DebridCore/Tests/DebridCoreTests/DomainHashableTests.swift
git commit -m "feat(core): Hashable on domain models for value-based navigation" \
  -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Brain — source quality ranker

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Library/MediaSourceRanking.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/MediaSourceRankingTests.swift` (create)

- [ ] **Step 1: Write the failing test** — create `MediaSourceRankingTests.swift`:

```swift
import Testing
import DebridCore

@Suite struct MediaSourceRankingTests {
    private func src(_ id: String, _ res: String?, _ source: String? = nil, _ codec: String? = nil) -> MediaSource {
        MediaSource(torrentID: id, fileID: nil, restrictedLink: "l",
                    parsed: ParsedRelease(title: "t", resolution: res, source: source, videoCodec: codec))
    }

    @Test func ordersByResolutionThenSourceThenCodec() {
        let s2160 = src("a", "2160p", "REMUX", "HEVC")   // 40702
        let s1080blu = src("c", "1080p", "BluRay", "x265") // 30602
        let s1080web = src("b", "1080p", "WEB-DL", "x264") // 30501
        let s720 = src("d", "720p")                        // 20000
        #expect([s720, s1080web, s2160, s1080blu].bestFirst().map(\.torrentID) == ["a", "c", "b", "d"])
    }

    @Test func bestPicksHighest() {
        #expect([src("a", "1080p"), src("b", "2160p")].best?.torrentID == "b")
    }

    @Test func tieBreaksByTorrentIDForStableOrder() {
        let x = src("z", "1080p", "WEB-DL", "x264")
        let y = src("a", "1080p", "WEB-DL", "x264")
        #expect([x, y].bestFirst().map(\.torrentID) == ["a", "z"])
    }

    @Test func unknownFieldsRankLowest() {
        #expect([src("b", nil), src("a", "1080p")].bestFirst().map(\.torrentID) == ["a", "b"])
    }

    @Test func emptyHasNoBest() {
        #expect([MediaSource]().best == nil)
    }
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `swift test --package-path Packages/DebridCore --filter MediaSourceRankingTests`
Expected: FAIL — `value of type '[MediaSource]' has no member 'bestFirst'`.

- [ ] **Step 3: Implement the ranker** — create `MediaSourceRanking.swift`. The tier strings match `FilenameParser`'s canonical normalized forms exactly (case-sensitive):

```swift
/// Quality ranking for picking the default ("best") source and ordering the Versions list.
/// Pure and deterministic; tiers match `FilenameParser`'s canonical normalized tokens.
public extension MediaSource {
    /// Higher is better. Resolution dominates, then source tier, then video codec.
    var qualityRank: Int {
        Self.resolutionTier(parsed.resolution) * 10_000
            + Self.sourceTier(parsed.source) * 100
            + Self.codecTier(parsed.videoCodec)
    }

    static func resolutionTier(_ r: String?) -> Int {
        switch r {                 // ParsedRelease stores resolution lowercased
        case "2160p": return 4
        case "1080p": return 3
        case "720p": return 2
        case "480p": return 1
        default: return 0
        }
    }

    static func sourceTier(_ s: String?) -> Int {
        switch s {                 // FilenameParser.normalizeSource canonical forms
        case "REMUX": return 7
        case "BluRay": return 6
        case "WEB-DL": return 5
        case "WEBRip": return 4
        case "BDRip": return 3
        case "HDTV": return 2
        case "HDRip", "DVDRip": return 1
        default: return 0
        }
    }

    static func codecTier(_ c: String?) -> Int {
        switch c {                 // FilenameParser.normalizeVideo canonical forms
        case "HEVC", "x265", "h265": return 2
        case "AVC", "x264", "h264": return 1
        default: return 0
        }
    }
}

public extension Array where Element == MediaSource {
    /// Sources best-first. Deterministic: ties break by torrentID, then fileID.
    func bestFirst() -> [MediaSource] {
        sorted { a, b in
            if a.qualityRank != b.qualityRank { return a.qualityRank > b.qualityRank }
            if a.torrentID != b.torrentID { return a.torrentID < b.torrentID }
            return (a.fileID ?? -1) < (b.fileID ?? -1)
        }
    }

    /// The single best source, or nil when empty.
    var best: MediaSource? { bestFirst().first }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `swift test --package-path Packages/DebridCore --filter MediaSourceRankingTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Library/MediaSourceRanking.swift \
        Packages/DebridCore/Tests/DebridCoreTests/MediaSourceRankingTests.swift
git commit -m "feat(core): pure source quality ranker (bestFirst/best) for Versions" \
  -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Brain — TMDB season episodes + public inits on detail DTOs

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Metadata/TMDBModels.swift`
- Modify: `Packages/DebridCore/Sources/DebridCore/Metadata/TMDBClient.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/TMDBClientTests.swift` (modify)

- [ ] **Step 1: Write the failing test.** Open `TMDBClientTests.swift` and add this `@Test` inside the existing `@Suite struct TMDBClientTests { … }` body (it is already nested under `extension MockTests` and resets the handler in `init`):

```swift
@Test func fetchesSeasonEpisodes() async throws {
    MockURLProtocol.stub(status: 200, json: #"""
    {"season_number":1,"episodes":[
      {"episode_number":1,"name":"Winter Is Coming","overview":"Ned…",
       "still_path":"/s1.jpg","runtime":62,"air_date":"2011-04-17"},
      {"episode_number":2,"name":"The Kingsroad","overview":"The Lannisters…",
       "still_path":"/s2.jpg","runtime":56,"air_date":"2011-04-24"}
    ]}
    """#)
    let client = TMDBClient(apiKey: "KEY", http: HTTPClient(session: .mock))
    let season = try await client.tvSeasonDetails(tvID: 1399, season: 1)
    #expect(season.seasonNumber == 1)
    #expect(season.episodes.count == 2)
    #expect(season.episodes[0].name == "Winter Is Coming")
    #expect(season.episodes[0].runtime == 62)
    #expect(season.episodes[1].episodeNumber == 2)
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `swift test --package-path Packages/DebridCore --filter TMDBClientTests`
Expected: FAIL — `value of type 'TMDBClient' has no member 'tvSeasonDetails'`.

- [ ] **Step 3: Add the models + public inits.** In `TMDBModels.swift`, add the two new types at the end of the file:

```swift
/// One episode from a TMDB `/tv/{id}/season/{n}` response.
public struct TMDBEpisodeDetails: Decodable, Sendable, Equatable, Hashable, Identifiable {
    public let episodeNumber: Int
    public let name: String?
    public let overview: String?
    public let stillPath: String?
    public let runtime: Int?
    public let airDate: String?

    public var id: Int { episodeNumber }

    enum CodingKeys: String, CodingKey {
        case name, overview, runtime
        case episodeNumber = "episode_number"
        case stillPath = "still_path"
        case airDate = "air_date"
    }

    public init(episodeNumber: Int, name: String?, overview: String?,
                stillPath: String?, runtime: Int?, airDate: String?) {
        self.episodeNumber = episodeNumber
        self.name = name
        self.overview = overview
        self.stillPath = stillPath
        self.runtime = runtime
        self.airDate = airDate
    }
}

/// A TMDB `/tv/{id}/season/{n}` response — the episodes for one season.
public struct TMDBSeasonDetails: Decodable, Sendable, Equatable {
    public let seasonNumber: Int
    public let episodes: [TMDBEpisodeDetails]

    enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
        case episodes
    }

    public init(seasonNumber: Int, episodes: [TMDBEpisodeDetails]) {
        self.seasonNumber = seasonNumber
        self.episodes = episodes
    }
}
```

Still in `TMDBModels.swift`, add public memberwise inits so the app's test fakes can construct these DTOs. Add to `TMDBGenre` (after its `name` property):

```swift
    public init(id: Int, name: String) { self.id = id; self.name = name }
```

Add to `TMDBMovieDetails` (after its `CodingKeys`):

```swift
    public init(id: Int, title: String, releaseDate: String?, overview: String?,
                posterPath: String?, backdropPath: String?, runtime: Int?,
                genres: [TMDBGenre], voteAverage: Double?) {
        self.id = id; self.title = title; self.releaseDate = releaseDate
        self.overview = overview; self.posterPath = posterPath; self.backdropPath = backdropPath
        self.runtime = runtime; self.genres = genres; self.voteAverage = voteAverage
    }
```

Add to `TMDBTVDetails` (after its `CodingKeys`):

```swift
    public init(id: Int, name: String, firstAirDate: String?, overview: String?,
                posterPath: String?, backdropPath: String?, numberOfSeasons: Int?,
                genres: [TMDBGenre], voteAverage: Double?) {
        self.id = id; self.name = name; self.firstAirDate = firstAirDate
        self.overview = overview; self.posterPath = posterPath; self.backdropPath = backdropPath
        self.numberOfSeasons = numberOfSeasons; self.genres = genres; self.voteAverage = voteAverage
    }
```

- [ ] **Step 4: Add the client method.** In `TMDBClient.swift`, add after `tvDetails(id:)`:

```swift
    public func tvSeasonDetails(tvID: Int, season: Int) async throws -> TMDBSeasonDetails {
        try await get("tv/\(tvID)/season/\(season)", [])
    }
```

- [ ] **Step 5: Run the test to confirm it passes**

Run: `swift test --package-path Packages/DebridCore --filter TMDBClientTests`
Expected: PASS (existing TMDB tests + the new `fetchesSeasonEpisodes`).

- [ ] **Step 6: Run the full brain suite + zero-warning check**

Run: `swift test --package-path Packages/DebridCore`
Expected: PASS (all suites — 112 prior + the new tests).
Run: `swift build --package-path Packages/DebridCore 2>&1 | grep -i warning`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Metadata/TMDBModels.swift \
        Packages/DebridCore/Sources/DebridCore/Metadata/TMDBClient.swift \
        Packages/DebridCore/Tests/DebridCoreTests/TMDBClientTests.swift
git commit -m "feat(core): TMDB tvSeasonDetails endpoint + public inits on detail DTOs" \
  -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: App — seams, PlaybackRequest, and the DetailStore (TDD)

**Files:**
- Create: `Apps/SeretTV/Detail/MediaDetailsProviding.swift`
- Create: `Apps/SeretTV/Detail/WatchProgressProviding.swift`
- Create: `Apps/SeretTV/Playback/PlaybackRequest.swift`
- Create: `Apps/SeretTV/Detail/DetailStore.swift`
- Test: `Apps/SeretTVTests/DetailStoreTests.swift` (create)

> The store + seams + `PlaybackRequest` compile independently of the views, so this task builds and tests on its own.

- [ ] **Step 1: Create the seams + PlaybackRequest first (the test references them).**

`Apps/SeretTV/Detail/MediaDetailsProviding.swift`:

```swift
import DebridCore

/// Thin Sendable seam over the brain's TMDB detail calls, so `DetailStore` is unit-testable
/// without the network. Mirrors 7b-i's `LibraryProviding`.
protocol MediaDetailsProviding: Sendable {
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails]
}

/// Production conformance — delegates straight to `TMDBClient`.
struct TMDBDetailsService: MediaDetailsProviding {
    let client: TMDBClient
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
        try await client.movieDetails(id: tmdbID)
    }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
        try await client.tvDetails(id: tmdbID)
    }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] {
        try await client.tvSeasonDetails(tvID: tvID, season: season).episodes
    }
}
```

`Apps/SeretTV/Detail/WatchProgressProviding.swift`:

```swift
import DebridCore
import Foundation

/// Sendable seam over `WatchProgressStore` so `DetailStore` reads/writes progress without
/// pulling SwiftData into the app's unit tests.
protocol WatchProgressProviding: Sendable {
    func progress(forContentKey key: String) async throws -> WatchState?
    func record(contentKey: String, sourceKey: String,
                positionSeconds: Double, durationSeconds: Double, finished: Bool) async throws
}

extension WatchProgressStore: WatchProgressProviding {
    // `progress(forContentKey:)` already satisfies the requirement (actor-isolated witness).
    // Provide the no-`at:` overload the seam declares; stamp the time here.
    public func record(contentKey: String, sourceKey: String,
                       positionSeconds: Double, durationSeconds: Double, finished: Bool) throws {
        try record(contentKey: contentKey, sourceKey: sourceKey,
                   positionSeconds: positionSeconds, durationSeconds: durationSeconds,
                   finished: finished, at: Date())
    }
}
```

`Apps/SeretTV/Playback/PlaybackRequest.swift`:

```swift
import DebridCore

/// The intent to play a specific file at a specific position. 7b-ii routes this to a
/// placeholder; Plan 7c's player consumes the same value. `Hashable` so it drives
/// `navigationDestination(for:)`.
struct PlaybackRequest: Hashable {
    let item: MediaItem
    let source: MediaSource
    let resumeAt: Double?   // seconds; nil = from the start
    let label: String       // e.g. "Dune: Part Two" or "Game of Thrones — S1·E3"
}
```

- [ ] **Step 2: Write the failing `DetailStore` tests** — create `Apps/SeretTVTests/DetailStoreTests.swift`:

```swift
import Testing
import Foundation
import DebridCore
@testable import Seret

// MARK: - Fixtures

private func parsed(_ res: String?) -> ParsedRelease { ParsedRelease(title: "t", resolution: res) }
private func source(_ id: String, _ res: String?) -> MediaSource {
    MediaSource(torrentID: id, fileID: nil, restrictedLink: "https://rd/\(id)", parsed: parsed(res))
}
private func movie(_ id: String, tmdb: Int? = 100, sources: [MediaSource]) -> MediaItem {
    MediaItem(id: id, kind: .movie, title: "Movie \(id)", year: 2024, sources: sources, seasons: [], tmdbID: tmdb)
}
private func show(_ id: String, tmdb: Int? = 200, seasons: [Season]) -> MediaItem {
    MediaItem(id: id, kind: .show, title: "Show \(id)", year: 2020, sources: [], seasons: seasons, tmdbID: tmdb)
}
private func episode(_ s: Int, _ n: Int, _ torrent: String) -> Episode {
    Episode(season: s, number: n, source: source(torrent, "1080p"))
}
private func movieDetails() -> TMDBMovieDetails {
    TMDBMovieDetails(id: 100, title: "Movie", releaseDate: "2024-01-01", overview: "Rich overview",
                     posterPath: "/p.jpg", backdropPath: "/b.jpg", runtime: 120,
                     genres: [TMDBGenre(id: 1, name: "Action")], voteAverage: 7.0)
}
private func tvDetails() -> TMDBTVDetails {
    TMDBTVDetails(id: 200, name: "Show", firstAirDate: "2020-01-01", overview: "Show overview",
                  posterPath: "/p.jpg", backdropPath: "/tb.jpg", numberOfSeasons: 1,
                  genres: [TMDBGenre(id: 18, name: "Drama")], voteAverage: 8.0)
}

private enum FakeError: Error { case boom }

private final class FakeDetails: MediaDetailsProviding {
    let movie: Result<TMDBMovieDetails, FakeError>
    let tv: Result<TMDBTVDetails, FakeError>
    let seasons: [Int: Result<[TMDBEpisodeDetails], FakeError>]
    init(movie: Result<TMDBMovieDetails, FakeError> = .failure(.boom),
         tv: Result<TMDBTVDetails, FakeError> = .failure(.boom),
         seasons: [Int: Result<[TMDBEpisodeDetails], FakeError>] = [:]) {
        self.movie = movie; self.tv = tv; self.seasons = seasons
    }
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { try movie.get() }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { try tv.get() }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] {
        try (seasons[season] ?? .success([])).get()
    }
}

private actor FakeWatch: WatchProgressProviding {
    private var rows: [String: WatchState]
    init(_ seed: [String: WatchState] = [:]) { rows = seed }
    func progress(forContentKey key: String) async throws -> WatchState? { rows[key] }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool) async throws {
        rows[contentKey] = WatchState(contentKey: contentKey, sourceKey: sourceKey,
                                      positionSeconds: positionSeconds, durationSeconds: durationSeconds,
                                      finished: finished, updatedAt: Date(timeIntervalSince1970: 0))
    }
}

// MARK: - Tests

@MainActor
@Suite struct DetailStoreTests {
    @Test func movieBaseThenRichFills() async {
        let m = movie("1", sources: [source("t", "1080p")])
        let store = DetailStore(item: m, details: FakeDetails(movie: .success(movieDetails())), watch: nil)
        #expect(store.richState == .idle)              // nothing fetched yet
        await store.load()
        #expect(store.richState == .loaded)
        #expect(store.backdropPath == "/b.jpg")
        #expect(store.runtime == 120)
        #expect(store.genres == ["Action"])
        #expect(store.overview == "Rich overview")
    }

    @Test func movieRichFailureKeepsBase() async {
        let m = movie("1", sources: [source("t", "1080p")])
        let store = DetailStore(item: m, details: FakeDetails(movie: .failure(.boom)), watch: nil)
        await store.load()
        #expect(store.richState == .failed)
        #expect(store.runtime == nil)                  // base retained, no crash
    }

    @Test func noTMDBIDSkipsFetchStaysLoaded() async {
        let m = movie("1", tmdb: nil, sources: [source("t", "1080p")])
        let store = DetailStore(item: m, details: FakeDetails(), watch: nil)
        await store.load()
        #expect(store.richState == .loaded)
    }

    @Test func versionsBestFirstAndBestIsTop() {
        let m = movie("1", sources: [source("a", "720p"), source("b", "2160p"), source("c", "1080p")])
        let store = DetailStore(item: m, details: FakeDetails(), watch: nil)
        #expect(store.versions.map(\.torrentID) == ["b", "c", "a"])
        #expect(store.bestSource?.torrentID == "b")
    }

    @Test func showLoadsSelectedSeasonEpisodes() async {
        let sh = show("9", seasons: [Season(number: 1, episodes: [episode(1, 1, "t1"), episode(1, 2, "t2")])])
        let eps = [TMDBEpisodeDetails(episodeNumber: 1, name: "Pilot", overview: "o",
                                      stillPath: "/s.jpg", runtime: 50, airDate: "2020-01-01")]
        let store = DetailStore(item: sh,
                                details: FakeDetails(tv: .success(tvDetails()), seasons: [1: .success(eps)]),
                                watch: nil)
        await store.load()
        #expect(store.richState == .loaded)
        #expect(store.selectedSeason == 1)
        #expect(store.episodeMeta[1]?[1]?.name == "Pilot")
    }

    @Test func markWatchedWritesAndReadsBack() async {
        let m = movie("1", sources: [source("t", "1080p")])
        let store = DetailStore(item: m, details: FakeDetails(movie: .success(movieDetails())), watch: FakeWatch())
        await store.load()
        let key = WatchKey.content(forMovie: m)
        #expect(store.watchState(forKey: key) == nil)
        await store.setWatched(true, contentKey: key, source: m.sources[0])
        #expect(store.watchState(forKey: key)?.finished == true)
        await store.setWatched(false, contentKey: key, source: m.sources[0])
        #expect(store.watchState(forKey: key)?.finished == false)
    }

    @Test func resumeReflectedInPlayRequest() async {
        let m = movie("1", sources: [source("t", "1080p")])
        let key = WatchKey.content(forMovie: m)
        let seeded = WatchState(contentKey: key, sourceKey: WatchKey.source(m.sources[0]),
                                positionSeconds: 600, durationSeconds: 1200, finished: false,
                                updatedAt: Date(timeIntervalSince1970: 0))
        let store = DetailStore(item: m, details: FakeDetails(movie: .success(movieDetails())),
                                watch: FakeWatch([key: seeded]))
        await store.load()
        #expect(store.playRequest(source: m.sources[0], episode: nil, label: m.title).resumeAt == 600)
        #expect(store.playRequest(source: m.sources[0], episode: nil, label: m.title, fromStart: true).resumeAt == nil)
    }

    @Test func finishedDoesNotResume() async {
        let m = movie("1", sources: [source("t", "1080p")])
        let key = WatchKey.content(forMovie: m)
        let seeded = WatchState(contentKey: key, sourceKey: WatchKey.source(m.sources[0]),
                                positionSeconds: 1200, durationSeconds: 1200, finished: true,
                                updatedAt: Date(timeIntervalSince1970: 0))
        let store = DetailStore(item: m, details: FakeDetails(movie: .success(movieDetails())),
                                watch: FakeWatch([key: seeded]))
        await store.load()
        #expect(store.playRequest(source: m.sources[0], episode: nil, label: m.title).resumeAt == nil)
    }
}
```

- [ ] **Step 3: Generate the project and run the tests to confirm they fail**

Run: `xcodegen generate`
Run: `xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' test`
Expected: FAIL — `cannot find 'DetailStore' in scope`.

- [ ] **Step 4: Implement `DetailStore`** — create `Apps/SeretTV/Detail/DetailStore.swift`:

```swift
import DebridCore
import Observation

/// The Detail screen's source of truth for one title. Renders instantly from the cached
/// `MediaItem`, then enriches on-demand from TMDB and loads watch state. Degrades silently
/// on failure (keeps base info), mirroring 7b-i's `LibraryStore`.
@MainActor
@Observable
final class DetailStore {
    enum RichState: Equatable { case idle, loading, loaded, failed }

    let item: MediaItem
    private let details: MediaDetailsProviding
    private let watch: WatchProgressProviding?

    private(set) var richState: RichState = .idle
    private(set) var backdropPath: String?
    private(set) var runtime: Int?
    private(set) var genres: [String] = []
    private(set) var overview: String?
    private(set) var selectedSeason: Int
    private(set) var episodeMeta: [Int: [Int: TMDBEpisodeDetails]] = [:]   // season → epNo → meta
    private(set) var watchByKey: [String: WatchState] = [:]                // contentKey → state

    init(item: MediaItem, details: MediaDetailsProviding, watch: WatchProgressProviding?) {
        self.item = item
        self.details = details
        self.watch = watch
        self.overview = item.overview
        self.backdropPath = item.backdropPath
        self.selectedSeason = item.seasons.first?.number ?? 1
    }

    // Movies: ranked sources.
    var versions: [MediaSource] { item.sources.bestFirst() }
    var bestSource: MediaSource? { item.sources.best }

    func load() async {
        await loadWatch()
        guard let tmdbID = item.tmdbID else { richState = .loaded; return }
        richState = .loading
        do {
            switch item.kind {
            case .movie:
                let d = try await details.movieDetails(tmdbID: tmdbID)
                backdropPath = d.backdropPath ?? backdropPath
                runtime = d.runtime
                genres = d.genres.map(\.name)
                overview = d.overview ?? overview
            case .show:
                let d = try await details.tvDetails(tmdbID: tmdbID)
                backdropPath = d.backdropPath ?? backdropPath
                genres = d.genres.map(\.name)
                overview = d.overview ?? overview
                await loadSeason(selectedSeason, tvID: tmdbID)
            }
            richState = .loaded
        } catch {
            richState = .failed          // keep base info; no error wall
        }
    }

    func selectSeason(_ n: Int) async {
        selectedSeason = n
        await loadWatchForSeason(n)
        guard episodeMeta[n] == nil, let tvID = item.tmdbID else { return }
        await loadSeason(n, tvID: tvID)
    }

    func watchState(forKey key: String) -> WatchState? { watchByKey[key] }

    /// Mark a movie or episode watched/unwatched. `source` records the exact file (sourceKey).
    func setWatched(_ watched: Bool, contentKey: String, source: MediaSource) async {
        guard let watch else { return }
        try? await watch.record(contentKey: contentKey, sourceKey: WatchKey.source(source),
                                positionSeconds: 0, durationSeconds: 0, finished: watched)
        await refreshWatch(contentKey)
    }

    /// Build a playback request for a movie source or an episode.
    func playRequest(source: MediaSource, episode: Episode?, label: String,
                     fromStart: Bool = false) -> PlaybackRequest {
        let key = episode.map { WatchKey.content(forShow: item, episode: $0) }
            ?? WatchKey.content(forMovie: item)
        let resume: Double? = fromStart ? nil : watchByKey[key].flatMap {
            (!$0.finished && $0.positionSeconds > 0) ? $0.positionSeconds : nil
        }
        return PlaybackRequest(item: item, source: source, resumeAt: resume, label: label)
    }

    /// Best-effort "what to play next" for a show's hero: first in-progress episode (series
    /// order), else the first not-known-finished episode, else the very first. Uses whatever
    /// watch state is currently loaded.
    func nextEpisode() -> Episode? {
        let all = item.seasons.sorted { $0.number < $1.number }.flatMap(\.episodes)
        if let inProgress = all.first(where: {
            let w = watchByKey[WatchKey.content(forShow: item, episode: $0)]
            return w.map { !$0.finished && $0.positionSeconds > 0 } ?? false
        }) { return inProgress }
        if let unfinished = all.first(where: {
            watchByKey[WatchKey.content(forShow: item, episode: $0)]?.finished != true
        }) { return unfinished }
        return all.first
    }

    // MARK: - Private

    private func loadSeason(_ n: Int, tvID: Int) async {
        do {
            let eps = try await details.seasonEpisodes(tvID: tvID, season: n)
            episodeMeta[n] = Dictionary(eps.map { ($0.episodeNumber, $0) }, uniquingKeysWith: { a, _ in a })
        } catch {
            // leave episodeMeta[n] nil → rows degrade to "Episode N"
        }
    }

    private func loadWatch() async {
        switch item.kind {
        case .movie: await refreshWatch(WatchKey.content(forMovie: item))
        case .show:  await loadWatchForSeason(selectedSeason)
        }
    }

    private func loadWatchForSeason(_ n: Int) async {
        guard let season = item.seasons.first(where: { $0.number == n }) else { return }
        for ep in season.episodes {
            await refreshWatch(WatchKey.content(forShow: item, episode: ep))
        }
    }

    private func refreshWatch(_ key: String) async {
        guard let watch else { return }
        watchByKey[key] = try? await watch.progress(forContentKey: key)
    }
}
```

- [ ] **Step 5: Generate + run the tests to confirm they pass**

Run: `xcodegen generate`
Run: `xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' test`
Expected: PASS (8 `DetailStoreTests` + the existing 9 `LibraryStoreTests`).

- [ ] **Step 6: Commit**

```bash
git add Apps/SeretTV/Detail/MediaDetailsProviding.swift \
        Apps/SeretTV/Detail/WatchProgressProviding.swift \
        Apps/SeretTV/Playback/PlaybackRequest.swift \
        Apps/SeretTV/Detail/DetailStore.swift \
        Apps/SeretTVTests/DetailStoreTests.swift
git commit -m "feat(tvos): DetailStore + details/watch seams + PlaybackRequest (TDD)" \
  -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: App — `AppSession` vends details provider + shared watch store

**Files:**
- Modify: `Apps/SeretTV/Shell/AppSession.swift`

> No unit test (matches 7b-i — `AppSession` is composition glue). Verified by build.

- [ ] **Step 1: Add the imports and stored providers.** In `AppSession.swift`, change the imports at the top to add SwiftData:

```swift
import DebridCore
import Foundation
import Observation
import SwiftData
```

Add these stored properties just below `private(set) var libraryStore: LibraryStore?` (line 20):

```swift
    /// On-demand TMDB detail provider for the Detail screen (nil while signed out).
    private(set) var detailsProvider: MediaDetailsProviding?

    /// Shared watch-progress store (nil while signed out, or if the container fails to build).
    /// 7c's player + a later Continue-Watching feed reuse this same instance.
    private(set) var watchStore: WatchProgressProviding?
```

- [ ] **Step 2: Set them in `enterSignedIn()`.** Replace the body of `enterSignedIn()` (lines 71–81) with:

```swift
    private func enterSignedIn() {
        guard state != .signedIn else { return }
        let tmdb = TMDBClient(apiKey: Secrets.tmdbAPIKey)
        let service = LibraryService(
            torrents: TorrentsClient(tokens: realDebrid),
            builder: LibraryBuilder(),
            enricher: MetadataEnricher(tmdb: tmdb),
            store: LibrarySnapshotStore(directory: Self.cachesDirectory))
        libraryStore = LibraryStore(library: service)
        detailsProvider = TMDBDetailsService(client: tmdb)
        watchStore = (try? ModelContainer(for: WatchProgress.self))
            .map { WatchProgressStore(modelContainer: $0) as WatchProgressProviding }
        state = .signedIn
    }
```

- [ ] **Step 3: Clear them in `enterSignedOut()`.** In `enterSignedOut()`, just below `libraryStore = nil` (line 65), add:

```swift
        detailsProvider = nil
        watchStore = nil
```

- [ ] **Step 4: Generate + build to confirm it compiles**

Run: `xcodegen generate`
Run: `xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Apps/SeretTV/Shell/AppSession.swift
git commit -m "feat(tvos): AppSession vends TMDB details provider + shared WatchProgressStore" \
  -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: App — navigation, placeholder, chips, DetailView + MovieDetailView

**Files:**
- Create: `Apps/SeretTV/Detail/QualityChips.swift`
- Create: `Apps/SeretTV/Detail/BackdropBackground.swift`
- Create: `Apps/SeretTV/Playback/PlayerPlaceholderView.swift`
- Create: `Apps/SeretTV/Detail/DetailView.swift`
- Create: `Apps/SeretTV/Detail/MovieDetailView.swift`
- Modify: `Apps/SeretTV/Library/PosterCard.swift`
- Modify: `Apps/SeretTV/Shell/LibraryShell.swift`

> Views aren't unit-tested; they are starting points verified (and focus/spacing tuned) in the tvOS simulator. Each file below compiles as written.

- [ ] **Step 1: `QualityChips.swift`**

```swift
import DebridCore
import SwiftUI

/// Renders the quality/source/codec chips for a parsed release.
struct QualityChips: View {
    let parsed: ParsedRelease

    var body: some View {
        HStack(spacing: 8) {
            ForEach(chips, id: \.self) { chip($0) }
        }
    }

    private var chips: [String] {
        [parsed.resolution, parsed.source, parsed.videoCodec, parsed.audioCodec].compactMap { $0 }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.white.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
    }
}
```

- [ ] **Step 2: `BackdropBackground.swift`**

```swift
import DebridCore
import SwiftUI

/// Full-screen backdrop (or poster fallback) with a darkening scrim, behind a Detail screen.
struct BackdropBackground: View {
    let path: String?            // TMDB backdrop path
    let posterFallback: String?

    var body: some View {
        image
            .overlay(scrim)
            .ignoresSafeArea()
    }

    @ViewBuilder private var image: some View {
        if let url = TMDBClient.imageURL(path: path, size: "w1280")
            ?? TMDBClient.imageURL(path: posterFallback, size: "w780") {
            AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                placeholder: { Color.black }
        } else {
            LinearGradient(colors: [.gray.opacity(0.3), .black], startPoint: .top, endPoint: .bottom)
        }
    }

    private var scrim: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(0.95), location: 0.0),
            .init(color: .black.opacity(0.45), location: 0.5),
            .init(color: .black.opacity(0.85), location: 1.0),
        ], startPoint: .leading, endPoint: .trailing)
    }
}
```

- [ ] **Step 3: `PlayerPlaceholderView.swift`**

```swift
import DebridCore
import SwiftUI

/// Stands in for the real player (Plan 7c). Renders the resolved playback intent so the
/// drill-down is verifiable end-to-end without playback. 7c replaces this destination.
struct PlayerPlaceholderView: View {
    let request: PlaybackRequest

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "play.tv").font(.system(size: 72)).foregroundStyle(.secondary)
            Text(request.label).font(.title.bold()).multilineTextAlignment(.center)
            QualityChips(parsed: request.source.parsed)
            Text(request.resumeAt.map { "Would resume at \(Self.timecode($0))" } ?? "Would play from the start")
                .font(.title3).foregroundStyle(.secondary)
            Text("The video player arrives in Plan 7c.").font(.callout).foregroundStyle(.tertiary)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Player")
    }

    /// `h:mm:ss` (or `m:ss` under an hour).
    static func timecode(_ seconds: Double) -> String {
        let s = Int(seconds)
        let (h, m, sec) = (s / 3600, (s % 3600) / 60, s % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
```

- [ ] **Step 4: `DetailView.swift`** (the `.show` branch is a temporary placeholder, replaced in Task 7)

```swift
import DebridCore
import SwiftUI

/// Owns the per-title `DetailStore` and routes to the movie or show layout.
struct DetailView: View {
    @State private var store: DetailStore

    init(item: MediaItem, details: MediaDetailsProviding, watch: WatchProgressProviding?) {
        _store = State(initialValue: DetailStore(item: item, details: details, watch: watch))
    }

    var body: some View {
        Group {
            switch store.item.kind {
            case .movie: MovieDetailView(store: store)
            case .show:  Text("Show detail — Task 7").font(.title)   // replaced in Task 7
            }
        }
        .task { await store.load() }
    }
}
```

- [ ] **Step 5: `MovieDetailView.swift`**

```swift
import DebridCore
import SwiftUI

/// Movie Detail: backdrop hero, metadata, overview, Play/Resume, Versions, Mark Watched.
struct MovieDetailView: View {
    let store: DetailStore

    private var item: MediaItem { store.item }
    private var contentKey: String { WatchKey.content(forMovie: item) }
    private var watch: WatchState? { store.watchState(forKey: contentKey) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                hero
                if store.versions.count > 1 { versionsSection }   // single source → no disclosure (spec §6)
            }
            .padding(60)
        }
        .background(BackdropBackground(path: store.backdropPath, posterFallback: item.posterPath))
        .navigationTitle(item.title)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer().frame(height: 220)        // let the backdrop breathe at the top
            Text(item.title).font(.system(size: 64, weight: .bold))
            Text(metaLine).font(.title3).foregroundStyle(.secondary)
            if let best = store.bestSource { QualityChips(parsed: best.parsed) }
            if let overview = store.overview {
                Text(overview).font(.title3).frame(maxWidth: 1100, alignment: .leading)
            }
            actions
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let y = item.year { parts.append(String(y)) }
        if let r = store.runtime { parts.append("\(r) min") }
        if !store.genres.isEmpty { parts.append(store.genres.prefix(3).joined(separator: " · ")) }
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 20) {
            if let best = store.bestSource {
                if let resume = resumeSeconds {
                    NavigationLink(value: store.playRequest(source: best, episode: nil, label: item.title)) {
                        Label("Resume \(PlayerPlaceholderView.timecode(resume))", systemImage: "play.fill")
                    }
                    NavigationLink(value: store.playRequest(source: best, episode: nil,
                                                            label: item.title, fromStart: true)) {
                        Label("Play from Start", systemImage: "gobackward")
                    }
                } else {
                    NavigationLink(value: store.playRequest(source: best, episode: nil, label: item.title)) {
                        Label("Play", systemImage: "play.fill")
                    }
                }
            }
            Button {
                Task {
                    await store.setWatched(!isWatched, contentKey: contentKey,
                                           source: store.bestSource ?? item.sources[0])
                }
            } label: {
                Label(isWatched ? "Mark Unwatched" : "Mark Watched",
                      systemImage: isWatched ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .disabled(item.sources.isEmpty)
        }
        .font(.title3)
    }

    private var resumeSeconds: Double? {
        guard let w = watch, !w.finished, w.positionSeconds > 0 else { return nil }
        return w.positionSeconds
    }
    private var isWatched: Bool { watch?.finished == true }

    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Versions").font(.title2.bold())
            ForEach(store.versions, id: \.self) { src in
                NavigationLink(value: store.playRequest(source: src, episode: nil, label: item.title)) {
                    HStack {
                        QualityChips(parsed: src.parsed)
                        Spacer()
                        Image(systemName: "play.circle")
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: 1100, alignment: .leading)
    }
}
```

- [ ] **Step 6: Wire `PosterCard` to navigate.** Replace the `body` of `PosterCard.swift` (lines 9–20) — swap `Button(action: {})` for a value `NavigationLink`, and update the doc comment on line 5:

```swift
/// One focusable poster tile (tvOS `.card` style gives the focus lift + ring).
/// Selecting it pushes the item's Detail screen (see `LibraryShell` navigationDestination).
struct PosterCard: View {
    let item: MediaItem

    var body: some View {
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 10) {
                poster
                Text(item.title)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(width: 220, alignment: .leading)
            }
        }
        .buttonStyle(.card)
    }
```

(Leave the `poster` and `placeholder` helpers unchanged.)

- [ ] **Step 7: Add the `NavigationStack` + destinations in `LibraryShell`.** In `LibraryShell.swift`, replace the `detail` computed property (lines 33–46) with a version that wraps each grid in a stack:

```swift
    @ViewBuilder private var detail: some View {
        if let store = session.libraryStore {
            switch selection {
            case .movies:   browse("Movies", store.movies, store)
            case .shows:    browse("Shows", store.shows, store)
            case .settings: SettingsView()
            }
        }
    }

    @ViewBuilder
    private func browse(_ title: String, _ items: [MediaItem], _ store: LibraryStore) -> some View {
        NavigationStack {
            LibraryScreen(title: title, items: items, state: store.state, onRetry: { store.retry() })
                .navigationDestination(for: MediaItem.self) { item in
                    if let details = session.detailsProvider {
                        DetailView(item: item, details: details, watch: session.watchStore)
                    }
                }
                .navigationDestination(for: PlaybackRequest.self) { request in
                    PlayerPlaceholderView(request: request)
                }
        }
    }
```

- [ ] **Step 8: Generate + build**

Run: `xcodegen generate`
Run: `xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 9: Run the full app test bundle (nothing regressed)**

Run: `xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' test`
Expected: PASS (`DetailStoreTests` + `LibraryStoreTests`).

- [ ] **Step 10: Simulator verification (checkpoint).** Add a `#Preview` to `MovieDetailView.swift` so the screen renders with sample data without RD/TMDB (TMDB images simply won't load in preview — the backdrop falls back to the gradient, which is the intended degraded state):

```swift
#Preview {
    let s = MediaSource(torrentID: "t", fileID: nil, restrictedLink: "l",
                        parsed: ParsedRelease(title: "Dune", resolution: "2160p",
                                              source: "REMUX", videoCodec: "HEVC"))
    let item = MediaItem(id: "1", kind: .movie, title: "Dune: Part Two", year: 2024,
                         sources: [s], seasons: [], tmdbID: nil,
                         overview: "Paul Atreides unites with the Fremen…")
    return NavigationStack {
        MovieDetailView(store: DetailStore(item: item, details: PreviewDetails(), watch: nil))
    }
}

/// Inert provider for previews (never called when tmdbID is nil).
private struct PreviewDetails: MediaDetailsProviding {
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw CancellationError() }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw CancellationError() }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
}
```

Open the preview (or run the app in the simulator and navigate a poster → Detail → Play) and confirm: hero title + chips + overview render, Play and Mark Watched are focusable, and Play pushes the placeholder. **Screenshot the rendered Detail.** (Live data with real posters shares the same one-time RD device-code sign-in deferred in 7a/7b-i.)

- [ ] **Step 11: Commit**

```bash
git add Apps/SeretTV/Detail/QualityChips.swift Apps/SeretTV/Detail/BackdropBackground.swift \
        Apps/SeretTV/Playback/PlayerPlaceholderView.swift Apps/SeretTV/Detail/DetailView.swift \
        Apps/SeretTV/Detail/MovieDetailView.swift Apps/SeretTV/Library/PosterCard.swift \
        Apps/SeretTV/Shell/LibraryShell.swift
git commit -m "feat(tvos): poster→Detail navigation, MovieDetailView, player placeholder" \
  -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: App — ShowDetailView + EpisodeRow

**Files:**
- Create: `Apps/SeretTV/Detail/ShowDetailView.swift`
- Create: `Apps/SeretTV/Detail/EpisodeRow.swift`
- Modify: `Apps/SeretTV/Detail/DetailView.swift` (route `.show` to `ShowDetailView`)

- [ ] **Step 1: `EpisodeRow.swift`**

```swift
import DebridCore
import SwiftUI

/// One episode in the vertical list: still + number/title + synopsis + progress, selectable
/// to play, with a context-menu Mark Watched/Unwatched.
struct EpisodeRow: View {
    let store: DetailStore
    let episode: Episode
    let meta: TMDBEpisodeDetails?

    private var contentKey: String { WatchKey.content(forShow: store.item, episode: episode) }
    private var watch: WatchState? { store.watchState(forKey: contentKey) }
    private var isWatched: Bool { watch?.finished == true }

    var body: some View {
        NavigationLink(value: store.playRequest(source: episode.source, episode: episode, label: label)) {
            HStack(alignment: .top, spacing: 20) {
                still
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(title).font(.title3.weight(.semibold))
                        if isWatched { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    if let overview = meta?.overview, !overview.isEmpty {
                        Text(overview).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                    progressBar
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .contextMenu {
            Button(isWatched ? "Mark Unwatched" : "Mark Watched") {
                Task { await store.setWatched(!isWatched, contentKey: contentKey, source: episode.source) }
            }
        }
        .frame(maxWidth: 1200, alignment: .leading)
    }

    private var label: String { "\(store.item.title) — S\(episode.season)·E\(episode.number)" }
    private var title: String { "\(episode.number) · \(meta?.name ?? "Episode \(episode.number)")" }
    private var subtitle: String {
        [meta?.runtime.map { "\($0) min" }, episode.source.parsed.resolution]
            .compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private var still: some View {
        Group {
            if let url = TMDBClient.imageURL(path: meta?.stillPath, size: "w300") {
                AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { Color.gray.opacity(0.3) }
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .frame(width: 214, height: 120).clipped().cornerRadius(8)
    }

    @ViewBuilder private var progressBar: some View {
        if isWatched {
            bar(fraction: 1, color: .green)
        } else if let w = watch, w.durationSeconds > 0, w.positionSeconds > 0 {
            bar(fraction: w.positionSeconds / w.durationSeconds, color: .white)
        }
    }

    private func bar(fraction: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(color).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(width: 214, height: 4)
    }
}
```

- [ ] **Step 2: `ShowDetailView.swift`**

```swift
import DebridCore
import SwiftUI

/// Show Detail: backdrop hero with Resume/Play-next, a focusable season picker, and the
/// vertical episode list for the selected season.
struct ShowDetailView: View {
    let store: DetailStore
    private var item: MediaItem { store.item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                hero
                seasonPicker
                episodeList
            }
            .padding(60)
        }
        .background(BackdropBackground(path: store.backdropPath, posterFallback: item.posterPath))
        .navigationTitle(item.title)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer().frame(height: 200)
            Text(item.title).font(.system(size: 60, weight: .bold))
            Text(metaLine).font(.title3).foregroundStyle(.secondary)
            if let overview = store.overview {
                Text(overview).font(.title3).frame(maxWidth: 1100, alignment: .leading)
            }
            heroActions
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let y = item.year { parts.append(String(y)) }
        if !store.genres.isEmpty { parts.append(store.genres.prefix(3).joined(separator: " · ")) }
        parts.append("\(item.seasons.count) Season\(item.seasons.count == 1 ? "" : "s")")
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder private var heroActions: some View {
        if let next = store.nextEpisode() {
            let resume = store.watchState(forKey: WatchKey.content(forShow: item, episode: next))
                .flatMap { (!$0.finished && $0.positionSeconds > 0) ? $0.positionSeconds : nil }
            NavigationLink(value: store.playRequest(
                source: next.source, episode: next,
                label: "\(item.title) — S\(next.season)·E\(next.number)")) {
                Label(resume != nil ? "Resume S\(next.season)·E\(next.number)"
                                    : "Play S\(next.season)·E\(next.number)",
                      systemImage: "play.fill")
            }
            .font(.title3)
        }
    }

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(item.seasons) { season in
                    Button { Task { await store.selectSeason(season.number) } } label: {
                        Text("Season \(season.number)").font(.title3.weight(.semibold))
                            .padding(.horizontal, 22).padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(season.number == store.selectedSeason ? .white : .gray)
                }
            }
        }
    }

    @ViewBuilder private var episodeList: some View {
        if let season = item.seasons.first(where: { $0.number == store.selectedSeason }) {
            VStack(spacing: 22) {
                ForEach(season.episodes) { ep in
                    EpisodeRow(store: store, episode: ep, meta: store.episodeMeta[season.number]?[ep.number])
                }
            }
        }
    }
}
```

- [ ] **Step 3: Route `.show` to `ShowDetailView`.** In `DetailView.swift`, replace the `.show` line:

```swift
            case .show:  ShowDetailView(store: store)
```

- [ ] **Step 4: Generate + build**

Run: `xcodegen generate`
Run: `xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Simulator verification (checkpoint).** Add a `#Preview` to `ShowDetailView.swift`:

```swift
#Preview {
    func ep(_ n: Int) -> Episode {
        Episode(season: 1, number: n,
                source: MediaSource(torrentID: "t\(n)", fileID: nil, restrictedLink: "l",
                                    parsed: ParsedRelease(title: "x", resolution: "1080p", source: "WEB-DL")))
    }
    let item = MediaItem(id: "9", kind: .show, title: "Game of Thrones", year: 2011, sources: [],
                         seasons: [Season(number: 1, episodes: [ep(1), ep(2), ep(3)])],
                         tmdbID: nil, overview: "Nine noble families fight for control…")
    return NavigationStack {
        ShowDetailView(store: DetailStore(item: item, details: PreviewDetailsShow(), watch: nil))
    }
}

private struct PreviewDetailsShow: MediaDetailsProviding {
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw CancellationError() }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw CancellationError() }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
}
```

Confirm: hero + Resume/Play-next, the season pills are focusable and the selected one is highlighted, the episode rows list with numbers/quality, selecting an episode pushes the placeholder, and the context menu marks watched (a ✓ + full bar appears). **Screenshot the rendered Show Detail.**

- [ ] **Step 6: Commit**

```bash
git add Apps/SeretTV/Detail/ShowDetailView.swift Apps/SeretTV/Detail/EpisodeRow.swift \
        Apps/SeretTV/Detail/DetailView.swift
git commit -m "feat(tvos): ShowDetailView + EpisodeRow (season picker, episode list, progress)" \
  -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Final verification — full suites, zero warnings, DoD

**Files:** none (verification + bookkeeping).

- [ ] **Step 1: Full brain suite**

Run: `swift test --package-path Packages/DebridCore`
Expected: PASS (all suites, including the new Hashable / ranker / season-decode tests).

- [ ] **Step 2: Zero-warning bar (brain)**

Run: `swift build --package-path Packages/DebridCore 2>&1 | grep -i warning`
Expected: no output.

- [ ] **Step 3: Full app test bundle**

Run: `xcodegen generate`
Run: `xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' test`
Expected: PASS (`DetailStoreTests` + `LibraryStoreTests`).

- [ ] **Step 4: Zero-warning bar (app).** Confirm the `xcodebuild` output above has no `warning:` lines.
Run: `xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build 2>&1 | grep -i "warning:"`
Expected: no output.

- [ ] **Step 5: DoD check against the spec (§8).** Confirm each box, using the Task 6/7 simulator screenshots as evidence:
  - Poster → Detail push; back restores grid focus.
  - Movie Detail: backdrop hero, year·runtime·genres, overview, chips, Versions, Play/Resume, Mark Watched.
  - Show Detail: hero, season picker, vertical episode list (still/title/synopsis/progress), per-episode Play + Mark Watched, hero Resume/Play-next.
  - Play pushes `PlayerPlaceholderView` with the resolved source + resume point (no playback).
  - Rich metadata fetched on-demand; `LibrarySnapshot` untouched; degrades silently without `tmdbID`/TMDB.
  - Mark Watched/Unwatched persists and updates the UI.

  (Live-data screenshots with real posters depend on the same one-time RD device-code sign-in deferred in 7a/7b-i; preview/sample-data screenshots satisfy the structural DoD now.)

- [ ] **Step 6: No commit** unless Step 5 surfaced a fix. The slice is ready for the whole-branch review + merge handled outside this plan (the `docs(claude):` status update is made at merge time, mirroring 7a/7b-i).

---

## Notes for the executor

- **tvOS focus/spacing** in the views (Task 6/7) are starting points — expect to nudge padding, focus styles, and the season-pill `.tint`/selection treatment while looking at the simulator. Behavior (navigation, data, watch writes) is locked by the `DetailStore` tests; visuals are tuned by eye.
- **Run the full brain suite**, never just `--filter`, before the final commit (the SwiftData SIGSEGV gotcha only shows under the full parallel run).
- **No new SwiftData test suites** are added here (the watch store is faked behind `WatchProgressProviding`), so the `SwiftDataSuite` parent is untouched.
- **Never** log RD tokens or unrestricted URLs; the placeholder shows the parsed quality + label only, never `restrictedLink`.
