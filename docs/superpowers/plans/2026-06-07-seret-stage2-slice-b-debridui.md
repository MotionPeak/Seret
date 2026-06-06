# Seret Stage 2 — Slice B (DebridUI stores) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add the two presentation view-models for Stage 2 to `Shared/DebridUI`: `SearchStore` (debounced TMDB search) and `AddStore` (fetch cached streams → pick best by original-language+quality → add to RD → optionally play), plus the provider seams they need, wired into `AppSession`.

**Architecture:** `@MainActor @Observable` stores mirroring `LibraryStore`/`DetailStore`. New `Sendable` seams (`SearchProviding`, `AddProviding`) wrap the DebridCore clients; `StreamSource` (already a DebridCore protocol) is injected directly. Host-free tests with fakes run under `swift test --package-path Shared/DebridUI`.

**Tech Stack:** Swift 6.3, Observation, Swift Testing. Depends on DebridCore Slice A (`CometStreamSource`, `CachedStream.rankedFor/bestMatch`, `TorrentsClient.add(magnetHash:)`, TMDB `originalLanguage`/`imdbID`).

---

## Context for the implementer

- **Run tests:** `swift test --package-path Shared/DebridUI`. Zero warnings: `swift build --package-path Shared/DebridUI 2>&1 | grep -i warning` prints nothing.
- **Store pattern (copy from `LibraryStore`):** `@MainActor @Observable public final class`, `private(set)` state props, a `State` enum, an `async load()`/action that is cancellation-aware (`try Task.checkCancellation()`), provider seams are `Sendable`.
- **Real Slice-A signatures to use (NOT the explore-agent's guesses):**
  - `TorrentsClient.add(magnetHash: String, maxPollAttempts: Int = 20, pollInterval: Duration = .seconds(1), sleep: ...) async throws -> TorrentInfo` — takes a **bare infohash**, builds the magnet internally.
  - `CometStreamSource.init(baseURL:http:tokens:parser:languages:)`, conforms to `StreamSource` with `streams(for: StreamQuery) async throws -> [CachedStream]`.
  - `[CachedStream].bestMatch(originalLanguage:) -> (stream: CachedStream, isFallback: Bool)?` and `.rankedFor(originalLanguage:)`.
  - `CachedStream { infoHash, fileIdx, rawTitle, parsed, languages, sizeBytes, sourceName }`.
  - `TMDBMovieDetails.originalLanguage/imdbID`, `TMDBTVDetails.originalLanguage/imdbID`.
- **Fakes pattern:** `Result<Value, Error>` containers conforming to the seams; tests are `@MainActor @Suite` with `async @Test`. See `Tests/DebridUITests/Fakes.swift`.
- **Commit style:** `feat(ui):` small atomic commits per task.

## File structure

```
Shared/DebridUI/Sources/DebridUI/
  Search/SearchProviding.swift     (CREATE: SearchProviding + TMDBSearchService)
  Search/SearchStore.swift         (CREATE)
  Add/AddProviding.swift           (CREATE: AddProviding + RealDebridAddService)
  Add/AddStore.swift               (CREATE)
  Shell/AppSession.swift           (MODIFY: vend searchStore + addStore)
Shared/DebridUI/Tests/DebridUITests/
  SearchStoreTests.swift           (CREATE)
  AddStoreTests.swift              (CREATE)
  Fakes.swift                      (MODIFY: add FakeSearch, FakeStreamSource, FakeAdd)
```

---

## Task B1: `SearchProviding` seam + `TMDBSearchService`

**Files:**
- Create: `Shared/DebridUI/Sources/DebridUI/Search/SearchProviding.swift`
- Test: covered indirectly by B2 (the seam is a thin pass-through). Add a compile-only smoke in B2's test file.

- [ ] **Step 1: Implement (no separate test — exercised via SearchStore in B2)**

```swift
import DebridCore

/// Searches TMDB for titles. Thin seam over `TMDBClient` so `SearchStore` is testable.
public protocol SearchProviding: Sendable {
    func searchMovie(query: String, year: Int?) async throws -> [TMDBSearchResult]
    func searchTV(query: String, firstAirYear: Int?) async throws -> [TMDBSearchResult]
}

public struct TMDBSearchService: SearchProviding {
    let client: TMDBClient
    public init(client: TMDBClient) { self.client = client }
    public func searchMovie(query: String, year: Int?) async throws -> [TMDBSearchResult] {
        try await client.searchMovie(query: query, year: year)
    }
    public func searchTV(query: String, firstAirYear: Int?) async throws -> [TMDBSearchResult] {
        try await client.searchTV(query: query, firstAirYear: firstAirYear)
    }
}
```

- [ ] **Step 2: Build** — `swift build --package-path Shared/DebridUI` (expect success, no warnings).
- [ ] **Step 3: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Search/SearchProviding.swift
git commit -m "feat(ui): add SearchProviding seam over TMDB search"
```

---

## Task B2: `SearchStore`

Debounced text search across movies + TV, merged best-first by TMDB popularity order (movies then TV, interleaved by vote average). States: `idle | searching | results | empty | failed`. Cancellation-aware so a newer query supersedes an in-flight one.

**Files:**
- Create: `Shared/DebridUI/Sources/DebridUI/Search/SearchStore.swift`
- Modify: `Shared/DebridUI/Tests/DebridUITests/Fakes.swift` (add `FakeSearch`)
- Test: `Shared/DebridUI/Tests/DebridUITests/SearchStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `Fakes.swift` (top-level, not `private`, so the test file can use it — match the file's existing visibility for shared fakes):

```swift
final class FakeSearch: SearchProviding {
    let movies: Result<[TMDBSearchResult], FakeError>
    let tv: Result<[TMDBSearchResult], FakeError>
    init(movies: Result<[TMDBSearchResult], FakeError> = .success([]),
         tv: Result<[TMDBSearchResult], FakeError> = .success([])) {
        self.movies = movies; self.tv = tv
    }
    func searchMovie(query: String, year: Int?) async throws -> [TMDBSearchResult] { try movies.get() }
    func searchTV(query: String, firstAirYear: Int?) async throws -> [TMDBSearchResult] { try tv.get() }
}
```

> If `FakeError` is `private` in `Fakes.swift`, change it to internal (drop `private`) so `FakeSearch`/`FakeAdd` and the new test files can reference it. Make existing fakes internal too if they were `private` and are now needed across files (they already live in `Fakes.swift`; only relax visibility as needed to compile).

Create `SearchStoreTests.swift`:

```swift
import Testing
import Foundation
import DebridCore
@testable import DebridUI

@MainActor
@Suite struct SearchStoreTests {
    func result(_ id: Int, _ title: String, vote: Double) -> TMDBSearchResult {
        TMDBSearchResult(id: id, title: title, name: nil, releaseDate: "2020-01-01",
                         firstAirDate: nil, posterPath: nil, overview: nil, voteAverage: vote)
    }

    @Test func emptyQueryStaysIdleAndClearsResults() async {
        let store = SearchStore(search: FakeSearch(movies: .success([result(1, "X", vote: 9)])))
        await store.search(query: "   ")
        #expect(store.state == .idle)
        #expect(store.results.isEmpty)
    }

    @Test func mergesMoviesAndTVBestVoteFirst() async {
        let store = SearchStore(search: FakeSearch(
            movies: .success([result(1, "Low", vote: 3)]),
            tv: .success([result(2, "High", vote: 8)])))
        await store.search(query: "matrix")
        #expect(store.state == .results)
        #expect(store.results.first?.id == 2)   // higher vote first
        #expect(store.results.count == 2)
    }

    @Test func noHitsIsEmpty() async {
        let store = SearchStore(search: FakeSearch())
        await store.search(query: "zzz")
        #expect(store.state == .empty)
    }

    @Test func failureSurfacesFailed() async {
        let store = SearchStore(search: FakeSearch(movies: .failure(.boom), tv: .failure(.boom)))
        await store.search(query: "matrix")
        if case .failed = store.state {} else { Issue.record("expected failed") }
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test --package-path Shared/DebridUI --filter SearchStoreTests` → FAIL (no `SearchStore`).

- [ ] **Step 3: Implement**

```swift
import DebridCore
import Observation

/// Debounced TMDB title search across movies + TV, merged best-first by vote average.
@MainActor
@Observable
public final class SearchStore {
    public enum State: Equatable { case idle, searching, results, empty, failed(String) }

    public private(set) var state: State = .idle
    public private(set) var results: [TMDBSearchResult] = []

    private let search: SearchProviding

    public init(search: SearchProviding) { self.search = search }

    /// Runs a search. Empty/whitespace query resets to idle. Cancellation-aware:
    /// a superseding call leaves state for the newer task.
    public func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { state = .idle; results = []; return }
        state = .searching
        do {
            async let movies = search.searchMovie(query: trimmed, year: nil)
            async let tv = search.searchTV(query: trimmed, firstAirYear: nil)
            let merged = try await (movies + tv).sorted { ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0) }
            try Task.checkCancellation()
            results = merged
            state = merged.isEmpty ? .empty : .results
        } catch is CancellationError {
            // superseded
        } catch {
            state = .failed("Search failed. Check your connection and try again.")
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test --package-path Shared/DebridUI --filter SearchStoreTests` → PASS (4 tests).
- [ ] **Step 5: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Search/SearchStore.swift \
        Shared/DebridUI/Tests/DebridUITests/SearchStoreTests.swift \
        Shared/DebridUI/Tests/DebridUITests/Fakes.swift
git commit -m "feat(ui): add SearchStore (debounced TMDB search, merged best-first)"
```

---

## Task B3: `AddProviding` seam + `RealDebridAddService`

Wraps the Slice-A `TorrentsClient.add(magnetHash:)`. Also exposes a `remove` for the cache-miss keep/remove path (RD `DELETE /torrents/delete/{id}` — add it to `TorrentsClient` if not present; see step note).

**Files:**
- Create: `Shared/DebridUI/Sources/DebridUI/Add/AddProviding.swift`
- (Possibly) Modify: `Packages/DebridCore/.../TorrentsClient.swift` to add `deleteTorrent(id:)` if remove is wired now (optional — can defer remove to Slice C).

- [ ] **Step 1: Implement**

```swift
import DebridCore

/// Adds an already-cached torrent (by infohash) to the user's RD account.
public protocol AddProviding: Sendable {
    func add(infoHash: String) async throws -> TorrentInfo
}

public struct RealDebridAddService: AddProviding {
    let torrents: TorrentsClient
    public init(torrents: TorrentsClient) { self.torrents = torrents }
    public func add(infoHash: String) async throws -> TorrentInfo {
        try await torrents.add(magnetHash: infoHash)
    }
}
```

- [ ] **Step 2: Build + Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Add/AddProviding.swift
git commit -m "feat(ui): add AddProviding seam over RD add"
```

---

## Task B4: `AddStore`

For a chosen TMDB title: fetch details (original_language + imdb_id) → fetch cached streams via `StreamSource` → `bestMatch` → expose best + full ranked list + `isFallback`. Actions: `loadStreams()`, `addBest()`, `add(stream:)`, and the result of an add (a `TorrentInfo`) so the app can refresh the library / build a `PlaybackRequest`.

**State:** `idle | loadingStreams | streams | noStreams | failed(String) | adding | added(TorrentInfo) | addFailed(String)`.

**Files:**
- Create: `Shared/DebridUI/Sources/DebridUI/Add/AddStore.swift`
- Modify: `Shared/DebridUI/Tests/DebridUITests/Fakes.swift` (add `FakeStreamSource`, `FakeAdd`)
- Test: `Shared/DebridUI/Tests/DebridUITests/AddStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `Fakes.swift`:

```swift
final class FakeStreamSource: StreamSource {
    let result: Result<[CachedStream], FakeError>
    init(_ result: Result<[CachedStream], FakeError>) { self.result = result }
    func streams(for query: StreamQuery) async throws -> [CachedStream] { try result.get() }
}

final class FakeAdd: AddProviding {
    let result: Result<TorrentInfo, FakeError>
    init(_ result: Result<TorrentInfo, FakeError>) { self.result = result }
    func add(infoHash: String) async throws -> TorrentInfo { try result.get() }
}

func cachedStream(_ hash: String, res: String, langs: [String], size: Int) -> CachedStream {
    CachedStream(infoHash: hash, fileIdx: nil, rawTitle: "t",
                 parsed: ParsedRelease(title: "t", resolution: res),
                 languages: langs, sizeBytes: size, sourceName: nil)
}
```

Create `AddStoreTests.swift`:

```swift
import Testing
import Foundation
import DebridCore
@testable import DebridUI

@MainActor
@Suite struct AddStoreTests {
    func tv(_ status: String = "downloaded") -> TorrentInfo {
        TorrentInfo(id: "T", filename: "M", hash: "h", bytes: 1, progress: 100, status: status,
                    files: [TorrentFile(id: 1, path: "/M/m.mkv", bytes: 1, selected: 1)],
                    links: ["https://rd/d/X"])
    }

    func store(streams: Result<[CachedStream], FakeError>,
               add: Result<TorrentInfo, FakeError> = .failure(.boom)) -> AddStore {
        AddStore(imdbID: "tt1", kind: .movie, originalLanguage: "fr",
                 streamSource: FakeStreamSource(streams), add: FakeAdd(add))
    }

    @Test func loadStreamsPicksOriginalLanguageBest() async {
        let s = store(streams: .success([
            cachedStream("a", res: "2160p", langs: ["en"], size: 100),
            cachedStream("b", res: "1080p", langs: ["fr"], size: 50)]))
        await s.loadStreams()
        #expect(s.state == .streams)
        #expect(s.best?.infoHash == "b")
        #expect(s.isFallback == false)
        #expect(s.ranked.count == 2)
    }

    @Test func loadStreamsFlagsFallbackWhenNoOriginal() async {
        let s = store(streams: .success([cachedStream("a", res: "2160p", langs: ["en"], size: 100)]))
        await s.loadStreams()
        #expect(s.best?.infoHash == "a")
        #expect(s.isFallback == true)
    }

    @Test func noStreamsState() async {
        let s = store(streams: .success([]))
        await s.loadStreams()
        #expect(s.state == .noStreams)
    }

    @Test func streamsFailureState() async {
        let s = store(streams: .failure(.boom))
        await s.loadStreams()
        if case .failed = s.state {} else { Issue.record("expected failed") }
    }

    @Test func addBestSucceeds() async {
        let s = store(streams: .success([cachedStream("b", res: "1080p", langs: ["fr"], size: 50)]),
                      add: .success(tv()))
        await s.loadStreams()
        await s.addBest()
        if case let .added(info) = s.state { #expect(info.id == "T") } else { Issue.record("expected added") }
    }

    @Test func addFailureSurfacesAddFailed() async {
        let s = store(streams: .success([cachedStream("b", res: "1080p", langs: ["fr"], size: 50)]),
                      add: .failure(.boom))
        await s.loadStreams()
        await s.addBest()
        if case .addFailed = s.state {} else { Issue.record("expected addFailed") }
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test --package-path Shared/DebridUI --filter AddStoreTests` → FAIL.

- [ ] **Step 3: Implement**

```swift
import DebridCore
import Observation

/// Drives the Add flow for one chosen title: fetch cached streams, rank by
/// original-language+quality, and add the pick to RD.
@MainActor
@Observable
public final class AddStore {
    public enum State: Equatable {
        case idle, loadingStreams, streams, noStreams, failed(String)
        case adding, added(TorrentInfo), addFailed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var ranked: [CachedStream] = []
    public private(set) var best: CachedStream?
    public private(set) var isFallback = false

    private let imdbID: String
    private let kind: StreamQuery.Kind
    private let originalLanguage: String?
    private let streamSource: StreamSource
    private let add: AddProviding

    public init(imdbID: String, kind: StreamQuery.Kind, originalLanguage: String?,
                streamSource: StreamSource, add: AddProviding) {
        self.imdbID = imdbID; self.kind = kind; self.originalLanguage = originalLanguage
        self.streamSource = streamSource; self.add = add
    }

    public func loadStreams() async {
        state = .loadingStreams
        do {
            let query = StreamQuery(imdbID: imdbID, kind: kind, originalLanguage: originalLanguage)
            let found = try await streamSource.streams(for: query)
            ranked = found.rankedFor(originalLanguage: originalLanguage)
            if let match = found.bestMatch(originalLanguage: originalLanguage) {
                best = match.stream; isFallback = match.isFallback; state = .streams
            } else {
                best = nil; isFallback = false; state = .noStreams
            }
        } catch {
            state = .failed("Couldn't find sources. Check your connection and try again.")
        }
    }

    public func addBest() async {
        guard let best else { return }
        await add(stream: best)
    }

    public func add(stream: CachedStream) async {
        state = .adding
        do {
            let info = try await add.add(infoHash: stream.infoHash)
            state = .added(info)
        } catch let RDAddError.notInstant(id) {
            state = .addFailed("That version isn't instantly available (RD id \(id)).")
        } catch {
            state = .addFailed("Couldn't add this to Real-Debrid. Try another version.")
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test --package-path Shared/DebridUI --filter AddStoreTests` → PASS (6 tests).
- [ ] **Step 5: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Add/AddStore.swift \
        Shared/DebridUI/Tests/DebridUITests/AddStoreTests.swift \
        Shared/DebridUI/Tests/DebridUITests/Fakes.swift
git commit -m "feat(ui): add AddStore (fetch cached streams, rank, add to RD)"
```

---

## Task B5: Wire `SearchStore` into `AppSession`; expose Add factory

`SearchStore` is a singleton per session. `AddStore` is **per-title** (built when the user opens an Add screen), so `AppSession` vends a **factory** for it (it needs the imdbID/kind/originalLanguage of the chosen title) plus the shared `StreamSource` + `AddProviding`.

**Files:**
- Modify: `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift`

- [ ] **Step 1: Read AppSession.swift, then add**

- a `searchStore: SearchStore?` `private(set)` property (nil when signed out).
- store `tmdb` + `torrents` on the session (the explore notes show they're built in `enterSignedIn()` already; keep references).
- in `enterSignedIn()`: 
  ```swift
  searchStore = SearchStore(search: TMDBSearchService(client: tmdb))
  streamSource = CometStreamSource(tokens: realDebrid)
  addService = RealDebridAddService(torrents: torrents)
  ```
- add a public factory:
  ```swift
  public func makeAddStore(imdbID: String, kind: StreamQuery.Kind, originalLanguage: String?) -> AddStore? {
      guard let streamSource, let addService else { return nil }
      return AddStore(imdbID: imdbID, kind: kind, originalLanguage: originalLanguage,
                      streamSource: streamSource, add: addService)
  }
  ```
- in `enterSignedOut()`: nil out `searchStore`, `streamSource`, `addService`.

- [ ] **Step 2: Build** — `swift build --package-path Shared/DebridUI` (no warnings). Also build the apps later in Slice C.
- [ ] **Step 3: Run the whole DebridUI suite** — `swift test --package-path Shared/DebridUI` → all green.
- [ ] **Step 4: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift
git commit -m "feat(ui): vend SearchStore + AddStore factory from AppSession"
```

---

## Slice B done — verification

- [ ] `swift test --package-path Shared/DebridUI` — all green (existing 48–50 + new SearchStore/AddStore tests).
- [ ] `swift build --package-path Shared/DebridUI 2>&1 | grep -i warning` — nothing.
- [ ] DebridCore still green (Slice A unaffected): `swift test --package-path Packages/DebridCore`.

## Notes / deferred to Slice C

- **Add & Play** (immediate playback after add) needs to build a `MediaItem` + `MediaSource` + `PlaybackRequest` from the returned `TorrentInfo` (filename → `ParsedRelease`, primary video file → `MediaSource.restrictedLink`). That construction is small but UI-adjacent; do it in Slice C where the player navigation lives, or add an `AddStore.playRequest(from:)` helper there. For Slice B, `addBest()` ending in `.added(TorrentInfo)` is the seam the UI consumes.
- **Cache-miss remove** (`RDAddError.notInstant`) currently just surfaces a message; wiring an actual RD `deleteTorrent(id:)` + keep/remove prompt is a Slice C affordance.
- After a successful add, Slice C should trigger `libraryStore` refresh so the title appears in the library.
