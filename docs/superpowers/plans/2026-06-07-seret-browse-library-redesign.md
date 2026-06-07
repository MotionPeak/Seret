# Seret Browse / My-Library Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline) or subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** Reframe the app around Browse (Movies/TV tabs = popular releases + in-tab search → add) vs My Library (own + play), with a CAM "In Theatres" section, "in library" badges, and trailers.

**Architecture:** Extend `TMDBClient` with popular/discover/videos endpoints; make `DiscoverStore` kind-aware; add ownership + trailer seams in DebridUI; rewire both apps' tab shells to Browse + My Library; per-platform trailer (iOS WKWebView, tvOS YouTube deep-link). Spec: `docs/superpowers/specs/2026-06-07-seret-browse-library-redesign.md`.

**Tech Stack:** Swift 6.3, Observation, Swift Testing, SwiftUI, XcodeGen.

**Verify:** `swift test --package-path Packages/DebridCore` + `--package-path Shared/DebridUI` (host-free, 0 warnings); `xcodebuild build` SeretTV (tvOS sim) + SeretMobile (iPhone sim), 0 warnings. Real browse/add/play/trailer = owner-pending.

---

## Slice D1 — DebridCore: TMDB browse + videos endpoints

### Task D1.1 — `TMDBVideo` model
**Files:** Modify `Packages/DebridCore/Sources/DebridCore/Metadata/TMDBModels.swift`; Test `Packages/DebridCore/Tests/DebridCoreTests/TMDBVideoTests.swift`

- [ ] Add model + helper:
```swift
public struct TMDBVideo: Decodable, Sendable, Equatable {
    public let key: String        // YouTube id
    public let site: String       // "YouTube"
    public let type: String       // "Trailer" / "Teaser"
    public let name: String?
    public init(key: String, site: String, type: String, name: String? = nil) {
        self.key = key; self.site = site; self.type = type; self.name = name
    }
}
public extension Array where Element == TMDBVideo {
    /// First YouTube Trailer, else first YouTube Teaser, else nil.
    var firstYouTubeTrailer: TMDBVideo? {
        let yt = filter { $0.site == "YouTube" }
        return yt.first { $0.type == "Trailer" } ?? yt.first { $0.type == "Teaser" }
    }
}
struct TMDBVideosResponse: Decodable { let results: [TMDBVideo] }
```
- [ ] Test `firstYouTubeTrailer` prefers Trailer over Teaser, ignores non-YouTube, returns nil when none.
- [ ] `swift test --package-path Packages/DebridCore --filter TMDBVideoTests` → pass. Commit `feat(core): add TMDBVideo + firstYouTubeTrailer`.

### Task D1.2 — `TMDBClient` browse + videos methods
**Files:** Modify `Packages/DebridCore/Sources/DebridCore/Metadata/TMDBClient.swift`; Test `…/TMDBClientTests.swift`

- [ ] Add:
```swift
public func popularMovies() async throws -> [TMDBSearchResult] {
    let r: TMDBSearchResponse = try await get("movie/popular", []); return r.results
}
public func popularTV() async throws -> [TMDBSearchResult] {
    let r: TMDBSearchResponse = try await get("tv/popular", []); return r.results
}
public func discoverTV(genreID: Int) async throws -> [TMDBSearchResult] {
    let r: TMDBSearchResponse = try await get("discover/tv", [
        URLQueryItem(name: "with_genres", value: String(genreID)),
        URLQueryItem(name: "sort_by", value: "popularity.desc"),
        URLQueryItem(name: "vote_count.gte", value: "100")]); return r.results
}
/// Home-release window for "New Releases" (dates are "YYYY-MM-DD").
public func discoverMovies(releaseFrom: String, releaseTo: String) async throws -> [TMDBSearchResult] {
    let r: TMDBSearchResponse = try await get("discover/movie", [
        URLQueryItem(name: "primary_release_date.gte", value: releaseFrom),
        URLQueryItem(name: "primary_release_date.lte", value: releaseTo),
        URLQueryItem(name: "sort_by", value: "primary_release_date.desc"),
        URLQueryItem(name: "vote_count.gte", value: "50")]); return r.results
}
public func movieVideos(id: Int) async throws -> [TMDBVideo] {
    let r: TMDBVideosResponse = try await get("movie/\(id)/videos", []); return r.results
}
public func tvVideos(id: Int) async throws -> [TMDBVideo] {
    let r: TMDBVideosResponse = try await get("tv/\(id)/videos", []); return r.results
}
```
- [ ] Tests (MockURLProtocol, mirror `discoversMoviesByGenre`): assert URL path + a decoded result for `popularMovies`, `popularTV`, `discoverTV` (`/discover/tv` + `with_genres`), `discoverMovies(releaseFrom:to:)` (`primary_release_date.gte/lte`), `movieVideos` (`/movie/1/videos` → a `TMDBVideo`).
- [ ] `swift test --package-path Packages/DebridCore` → all pass, 0 warnings. Commit `feat(core): add TMDB popular/discover-tv/release-window/videos endpoints`.

---

## Slice D2 — DebridUI: kind-aware discovery, search scoping, ownership, trailers

### Task D2.1 — `DiscoverProviding` extension + kind-aware `DiscoverStore`
**Files:** Modify `Shared/DebridUI/Sources/DebridUI/Search/DiscoverStore.swift`; Test `…/DiscoverStoreTests.swift`

- [ ] Replace `DiscoverProviding` with the broader seam + service:
```swift
public protocol DiscoverProviding: Sendable {
    func popularMovies() async throws -> [TMDBSearchResult]
    func popularTV() async throws -> [TMDBSearchResult]
    func nowPlaying() async throws -> [TMDBSearchResult]
    func newReleases(from: String, to: String) async throws -> [TMDBSearchResult]
    func moviesByGenre(_ id: Int) async throws -> [TMDBSearchResult]
    func tvByGenre(_ id: Int) async throws -> [TMDBSearchResult]
}
public struct TMDBDiscoverService: DiscoverProviding {
    let client: TMDBClient
    public init(client: TMDBClient) { self.client = client }
    public func popularMovies() async throws -> [TMDBSearchResult] { try await client.popularMovies() }
    public func popularTV() async throws -> [TMDBSearchResult] { try await client.popularTV() }
    public func nowPlaying() async throws -> [TMDBSearchResult] { try await client.nowPlayingMovies() }
    public func newReleases(from: String, to: String) async throws -> [TMDBSearchResult] {
        try await client.discoverMovies(releaseFrom: from, releaseTo: to) }
    public func moviesByGenre(_ id: Int) async throws -> [TMDBSearchResult] { try await client.discoverMovies(genreID: id) }
    public func tvByGenre(_ id: Int) async throws -> [TMDBSearchResult] { try await client.discoverTV(genreID: id) }
}
```
- [ ] `DiscoverStore` becomes kind-aware: `init(kind: MediaKind, discover: DiscoverProviding, now: @Sendable () -> Date = { Date() })`. Rows per kind:
  - `.movie`: Popular · In Theatres (`nowPlaying`) · New Releases (`newReleases(from:to:)` with window `now-300d … now-45d`, ISO `yyyy-MM-dd`) · genres [Action 28, Comedy 35, Horror 27, Drama 18, Thriller 53, Sci-Fi 878, Animation 16, Crime 80].
  - `.show`: Popular · genres [Drama 18, Comedy 35, Crime 80, Sci-Fi & Fantasy 10765, Animation 16, Mystery 9648, Reality 10764].
  - All hits tagged `SearchHit(result:, kind:)` with the store's kind. Concurrent load (order-preserving), empties dropped, `.failed` only if nothing loads. (Keep the existing `Row`/`State`/order-preserving TaskGroup pattern.)
- [ ] Update `DiscoverStoreTests` for the new `FakeDiscover` (all six methods) + kind. Cover: movie store builds Popular+InTheatres+NewReleases+genres, drops empty, Recently/Popular first; show store builds Popular+tv-genres; date window passed to `newReleases` is `now-300…now-45` (inject fixed `now`, assert the fake received plausible dates).
- [ ] `swift test --package-path Shared/DebridUI --filter DiscoverStoreTests` → pass. Commit `feat(ui): kind-aware DiscoverStore (movie/tv rows, In Theatres, New Releases)`.

### Task D2.2 — `SearchStore` kind scoping
**Files:** Modify `Shared/DebridUI/Sources/DebridUI/Search/SearchStore.swift`; Test `…/SearchStoreTests.swift`

- [ ] Add an optional kind filter: `public func search(query: String, kind: MediaKind? = nil) async` — when `kind` is set, only that endpoint runs and results are tagged that kind (movie tab → `searchMovie` only; tv tab → `searchTV` only). When nil, keep today's merged behavior. (Browse uses the kind-scoped call.)
- [ ] Test: `search(query:, kind: .movie)` returns only movie hits; `.show` only show hits; nil keeps merged.
- [ ] `swift test … --filter SearchStoreTests` → pass. Commit `feat(ui): scope SearchStore by media kind`.

### Task D2.3 — `LibraryStore.ownedTMDBIDs`
**Files:** Modify `Shared/DebridUI/Sources/DebridUI/Library/LibraryStore.swift`; Test `…/LibraryStoreTests.swift`

- [ ] Add: `public var ownedTMDBIDs: Set<Int> { Set((movies + shows).compactMap { $0.tmdbID }) }` and `public func ownedItem(tmdbID: Int) -> MediaItem? { (movies + shows).first { $0.tmdbID == tmdbID } }`.
- [ ] Test: after `apply`, ownedTMDBIDs contains the items' tmdbIDs; `ownedItem` returns the match.
- [ ] `swift test … --filter LibraryStoreTests` → pass. Commit `feat(ui): expose ownedTMDBIDs + ownedItem on LibraryStore`.

### Task D2.4 — `TrailerProviding` seam
**Files:** Create `Shared/DebridUI/Sources/DebridUI/Detail/TrailerProviding.swift`; Test `…/TrailerProvidingTests.swift`

- [ ] Implement:
```swift
import DebridCore
public protocol TrailerProviding: Sendable {
    func trailerKey(tmdbID: Int, kind: MediaKind) async -> String?
}
public struct TMDBTrailerService: TrailerProviding {
    let client: TMDBClient
    public init(client: TMDBClient) { self.client = client }
    public func trailerKey(tmdbID: Int, kind: MediaKind) async -> String? {
        let videos = try? await (kind == .movie ? client.movieVideos(id: tmdbID) : client.tvVideos(id: tmdbID))
        return videos?.firstYouTubeTrailer?.key
    }
}
```
- [ ] Test a fake `TMDBClient`? `TMDBClient` is a struct over `HTTPClient` — test `TMDBTrailerService` via `MockURLProtocol` is DebridCore-side; in DebridUI just smoke-compile. Instead unit-test the seam contract with a fake conforming type returning a key. (Keep it light — the real mapping is `firstYouTubeTrailer`, already tested in D1.1.)
- [ ] Commit `feat(ui): add TrailerProviding seam`.

### Task D2.5 — Wire `AppSession`
**Files:** Modify `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift`

- [ ] Replace `discoverStore` with `moviesBrowse` + `showsBrowse` (`DiscoverStore(kind:.movie/.show, discover:)`); add `trailers: TrailerProviding?`. Build all in `enterSignedIn()` from `tmdb`; nil in `enterSignedOut()`.
```swift
public private(set) var moviesBrowse: DiscoverStore?
public private(set) var showsBrowse: DiscoverStore?
public private(set) var trailers: TrailerProviding?
// enterSignedIn:
let discover = TMDBDiscoverService(client: tmdb)
moviesBrowse = DiscoverStore(kind: .movie, discover: discover)
showsBrowse = DiscoverStore(kind: .show, discover: discover)
trailers = TMDBTrailerService(client: tmdb)
```
- [ ] `swift test --package-path Shared/DebridUI` all green, 0 warnings. Commit `feat(ui): vend moviesBrowse/showsBrowse + trailers from AppSession`.

---

## Slice D3 — SeretMobile: tabs, Browse, My Library, trailer

### Task D3.1 — Trailer web player (iOS)
**Files:** Create `Apps/SeretMobile/Playback/TrailerView.swift`
- [ ] `TrailerView(youTubeKey: String)` = `UIViewRepresentable` over `WKWebView` loading `https://www.youtube.com/embed/{key}?autoplay=1&playsinline=1`, in a `NavigationStack`/sheet with a Done button. Build.

### Task D3.2 — Browse screen (shared per kind)
**Files:** Create `Apps/SeretMobile/Browse/BrowseScreen.swift`
- [ ] `BrowseScreen(kind: MediaKind)`: reads `session.moviesBrowse`/`showsBrowse` (by kind) + a kind-scoped `SearchStore` (use `session.searchStore`, call `search(query:kind:)`). Top gold search field (reuse the one from the old `SearchScreen`). Empty query → `DiscoverRails` over the kind's `DiscoverStore.rows`; non-empty → results grid. Each poster: if `session.libraryStore?.ownedTMDBIDs.contains(hit.result.id)` → "In Library" badge overlay + tap opens `router.detail = ownedItem`; else tap → `router.addHit = hit`. (Move `DiscoverRails`/poster cells out of the old SearchScreen into here.)
- [ ] Badge: small gold `Label("In Library", systemImage: "checkmark.circle.fill")` capsule pinned top-trailing on the `PosterCard`.

### Task D3.3 — My Library screen (split)
**Files:** Create `Apps/SeretMobile/Library/MyLibraryScreen.swift`
- [ ] A `Picker`/segmented control (Movies/TV) over `session.libraryStore` → reuses `LibraryGrid` with `store.movies` / `store.shows`. `.task(id: store.attempt) { await store.load() }`. Poster → `router.detail`.

### Task D3.4 — Rewire `MainShell` + trailer buttons
**Files:** Modify `Apps/SeretMobile/Shell/MainShell.swift`, `Apps/SeretMobile/Detail/MovieDetail.swift`/`ShowDetail.swift`, `Apps/SeretMobile/Search/AddScreen.swift`, `Apps/SeretMobile/Shell/RootView.swift`
- [ ] `Section` becomes `home, movies, tv, library, settings`. iPhone TabView + iPad sidebar: Home→`HomeScreen`, movies→`BrowseScreen(kind:.movie)`, tv→`BrowseScreen(kind:.show)`, library→`MyLibraryScreen`, settings→`SettingsView`. Remove the old `.search`/`.shows`/`.movies`(library) wiring; old `LibrarySection` usage moves into `MyLibraryScreen`.
- [ ] Add a **Trailer** button to MovieDetail/ShowDetail + AddScreen: `@State trailerKey`, `.task { trailerKey = await session.trailers?.trailerKey(tmdbID:, kind:) }`; button shown when non-nil → presents `TrailerView` in a sheet.
- [ ] `xcodegen generate` + `xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build` → 0 warnings. Commit `feat(mobile): Browse + My Library tabs, in-library badges, trailers`.

---

## Slice D4 — SeretTV: tabs, Browse, My Library, trailer

### Task D4.1 — Browse screen (tvOS)
**Files:** Create `Apps/SeretTV/Browse/BrowseScreen.swift`
- [ ] `BrowseScreen(kind:)`: `.searchable` scoped to kind (debounced `searchStore.search(query:kind:)`); empty → `DiscoverRowsView` over the kind's `DiscoverStore.rows` (move from old SearchScreen, focus-safe rails already done); non-empty → results grid. Owned poster → badge + `NavigationLink(value: ownedItem)` (library Detail); else `NavigationLink(value: hit)` (Add). Shell registers both `MediaItem` and `SearchHit` destinations (already does).

### Task D4.2 — My Library screen (tvOS)
**Files:** Create `Apps/SeretTV/Library/MyLibraryScreen.swift`
- [ ] Two focusable sub-tabs or a top Picker (Movies/TV) over `LibraryStore` → `LibraryScreen`/`PosterGrid` with `store.movies`/`store.shows`.

### Task D4.3 — Rewire `LibraryShell` + tvOS trailer + trailer buttons
**Files:** Modify `Apps/SeretTV/Shell/LibraryShell.swift`, `Apps/SeretTV/Detail/MovieDetailView.swift`/`ShowDetailView.swift`, `Apps/SeretTV/Search/AddScreen.swift`; Create `Apps/SeretTV/Playback/TrailerLauncher.swift`
- [ ] Tabs: `Movies` → `BrowseScreen(kind:.movie)`, `TV` → `BrowseScreen(kind:.show)`, `Library` → `MyLibraryScreen`, `Settings`. Remove old Search tab + the direct library grids.
- [ ] `TrailerLauncher`: `openYouTube(key:) { UIApplication.shared.open(URL(string:"youtube://watch?v=\(key)")!) }` with `canOpenURL` guard (fallback `https://`); a `trailerButton(key:)` helper shown only when openable. Add Trailer button to Detail + Add screens (key fetched via `session.trailers`).
- [ ] `xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build` → 0 warnings. Commit `feat(tv): Browse + My Library tabs, in-library badges, trailer deep-link`.

---

## Done — verification
- [ ] `swift test --package-path Packages/DebridCore` + `--package-path Shared/DebridUI` green, 0 warnings.
- [ ] `xcodebuild build` SeretTV + SeretMobile (iPhone) 0 warnings.
- [ ] ⚠️ OWNER-PENDING: on-device — Movies/TV browse + in-tab search, In Theatres vs New Releases, "In Library" badges, My Library split, trailers (iOS in-app, tvOS YouTube app).

## Notes
- "In Theatres" is a release-date proxy for CAM; real quality shows on the Add screen.
- Old `SearchScreen.swift` files are superseded by `BrowseScreen.swift` (delete after migration).
- Home tab (mobile) unchanged.
