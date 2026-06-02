# TMDB Enrichment + RD-fetch glue — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete `DebridCore`'s data layer — a `MetadataEnricher` that matches each grouped `MediaItem` to TMDB and fills `tmdbID` / title / `posterPath` / `overview` (degrading gracefully on lookup failure), and a `TorrentsClient.allTorrentInfos()` that turns the RD account into `[TorrentInfo]`. After this, the app composes `allTorrentInfos → LibraryBuilder.group → MetadataEnricher.enrich` to get an organized, metadata-rich library.

**Architecture:** `MetadataEnricher` is a `Sendable` value type over the existing `TMDBClient`. Per item it searches TMDB (movie vs TV by `kind`) and applies the best match via a new `MediaItem.withMetadata(...)`. `enrich(_ items:)` fans out concurrently with `withTaskGroup`, catching per-item errors so one failed lookup never fails the whole library. `allTorrentInfos()` paginates the torrents list then fetches each torrent's info concurrently (skipping any that fail). Tests mock the transport; multi-endpoint tests route by URL.

**Tech Stack:** Swift 6.3 (Swift 6 language mode), SPM, async/await, structured concurrency (`withTaskGroup`), Swift Testing.

**Plan 5 of the Seret roadmap.** After this the brain is feature-complete; next is Plan 6 — subtitles + SwiftData persistence + the `VideoPlayerEngine` protocol — then the apps.

> **v1 notes (documented):** enrichment takes the **first** TMDB result (TMDB sorts by relevance); title-similarity scoring is a follow-up. Backdrops come from a TMDB *details* call — deferred (search gives poster + overview, enough for v1). A systematic failure (e.g. bad API key) yields an all-unenriched-but-working library — acceptable degradation.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/DebridCore/Library/MetadataEnricher.swift` | `MediaItem.withMetadata(...)` + `MetadataEnricher` (enrich one / many) |
| `Sources/DebridCore/RealDebrid/TorrentsClient.swift` (modify) | `allTorrents()` (paginated) + `allTorrentInfos()` (concurrent info fan-out) |
| `Tests/DebridCoreTests/MetadataEnricherTests.swift` | Enrichment (nested under `MockTests`) |
| `Tests/DebridCoreTests/TorrentsClientAllInfosTests.swift` | RD glue with URL-routing mock (nested under `MockTests`) |

---

## Task 1: MediaItem.withMetadata + MetadataEnricher (single item)

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Library/MetadataEnricher.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/MetadataEnricherTests.swift`

- [ ] **Step 1: Write the failing test** (nested under `MockTests` — uses the TMDB mock)

`Tests/DebridCoreTests/MetadataEnricherTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct MetadataEnricherTests {
        init() { MockURLProtocol.handler = nil }

        private func movie(_ title: String, year: Int?) -> MediaItem {
            MediaItem(id: "movie:x", kind: .movie, title: title, year: year,
                      sources: [MediaSource(torrentID: "T", fileID: 1, restrictedLink: "https://rd/x",
                                            parsed: ParsedRelease(title: title))],
                      seasons: [])
        }

        private func enricher() -> MetadataEnricher {
            MetadataEnricher(tmdb: TMDBClient(apiKey: "K", http: HTTPClient(session: .mock)))
        }

        @Test func enrichesAMovieFromTMDB() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"results":[{"id":693134,"title":"Dune: Part Two","release_date":"2024-02-27",
              "poster_path":"/poster.jpg","overview":"Paul…","vote_average":8.3}]}
            """#)
            let result = try await enricher().enrich(movie("Dune Part Two", year: 2024))
            #expect(result.tmdbID == 693134)
            #expect(result.title == "Dune: Part Two")
            #expect(result.posterPath == "/poster.jpg")
            #expect(result.overview == "Paul…")
            #expect(result.id == "movie:tmdb:693134")
        }

        @Test func leavesItemUnchangedWhenNoMatch() async throws {
            MockURLProtocol.stub(status: 200, json: #"{"results":[]}"#)
            let original = movie("Totally Unknown Film", year: nil)
            let result = try await enricher().enrich(original)
            #expect(result == original)   // untouched
            #expect(result.tmdbID == nil)
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter MetadataEnricherTests`
Expected: FAIL — `MetadataEnricher` / `withMetadata` not defined.

- [ ] **Step 3: Implement `MetadataEnricher.swift`**

```swift
import Foundation

public extension MediaItem {
    /// Returns a copy carrying TMDB metadata. When `tmdbID` is non-nil the `id` switches
    /// to a stable TMDB-based key. `sources`, `seasons`, `year` are preserved.
    func withMetadata(tmdbID: Int?, title: String?, posterPath: String?, overview: String?) -> MediaItem {
        MediaItem(
            id: tmdbID.map { "\(kind.rawValue):tmdb:\($0)" } ?? id,
            kind: kind,
            title: title ?? self.title,
            year: year,
            sources: sources,
            seasons: seasons,
            tmdbID: tmdbID,
            posterPath: posterPath,
            backdropPath: backdropPath,
            overview: overview)
    }
}

/// Matches grouped `MediaItem`s to TMDB and fills their metadata. Degrades gracefully:
/// a failed or empty lookup leaves the item as-is (parsed title, no artwork).
public struct MetadataEnricher: Sendable {
    private let tmdb: TMDBClient

    public init(tmdb: TMDBClient) {
        self.tmdb = tmdb
    }

    /// Enriches a single item. Throws only if the TMDB call itself throws (the batch
    /// `enrich(_:)` below catches that per-item).
    public func enrich(_ item: MediaItem) async throws -> MediaItem {
        let results: [TMDBSearchResult]
        switch item.kind {
        case .movie:
            results = try await tmdb.searchMovie(query: item.title, year: item.year)
        case .show:
            results = try await tmdb.searchTV(query: item.title, firstAirYear: item.year)
        }
        guard let match = results.first else { return item }
        return item.withMetadata(tmdbID: match.id, title: match.displayTitle,
                                 posterPath: match.posterPath, overview: match.overview)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter MetadataEnricherTests`
Expected: PASS (2 tests). Full suite → 55 tests. No warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): MetadataEnricher + MediaItem.withMetadata (single-item TMDB match)"
```

---

## Task 2: MetadataEnricher — concurrent batch with graceful degradation

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Library/MetadataEnricher.swift`
- Modify: `Packages/DebridCore/Tests/DebridCoreTests/MetadataEnricherTests.swift`

- [ ] **Step 1: Write the failing tests** (add inside `MetadataEnricherTests`)

```swift
        @Test func enrichesAllItemsAndPreservesOrder() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"results":[{"id":1,"title":"Matched","release_date":"2020-01-01",
              "poster_path":"/p.jpg","overview":"o"}]}
            """#)
            let items = [movie("A", year: 2020), movie("B", year: 2020)]
            let result = await enricher().enrich(items)
            #expect(result.count == 2)
            #expect(result.allSatisfy { $0.tmdbID == 1 })
        }

        @Test func degradesGracefullyWhenTMDBFails() async throws {
            MockURLProtocol.stub(status: 500, json: #"{"error":"boom"}"#)
            let items = [movie("A", year: nil), movie("B", year: nil)]
            let result = await enricher().enrich(items)
            #expect(result.count == 2)
            #expect(result.allSatisfy { $0.tmdbID == nil })   // unenriched but present
            #expect(result.map(\.title) == ["A", "B"])         // order preserved
        }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter MetadataEnricherTests`
Expected: FAIL — `enrich(_ items:)` not defined.

- [ ] **Step 3: Implement the batch enrich**

Add to `MetadataEnricher` (after `enrich(_ item:)`):
```swift
    /// Enriches every item concurrently, preserving input order. Per-item lookup failures
    /// are swallowed — that item is returned unenriched rather than failing the whole batch.
    public func enrich(_ items: [MediaItem]) async -> [MediaItem] {
        await withTaskGroup(of: (Int, MediaItem).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    do { return (index, try await enrich(item)) }
                    catch { return (index, item) }
                }
            }
            var out = items
            for await (index, enriched) in group { out[index] = enriched }
            return out
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter MetadataEnricherTests`
Expected: PASS (4 tests). Full suite → 57 tests, stable (run twice). No warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): MetadataEnricher.enrich(_:) concurrent batch with graceful degradation"
```

---

## Task 3: TorrentsClient.allTorrentInfos — the RD-fetch glue

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/RealDebrid/TorrentsClient.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/TorrentsClientAllInfosTests.swift`

- [ ] **Step 1: Write the failing test** (nested under `MockTests`; routes responses by URL)

`Tests/DebridCoreTests/TorrentsClientAllInfosTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TorrentsClientAllInfosTests {
        init() { MockURLProtocol.handler = nil }

        struct StubTokens: AccessTokenProviding {
            func validAccessToken() async throws -> String { "TESTTOKEN" }
        }

        @Test func fetchesEveryTorrentsInfo() async throws {
            let listPage1 = #"""
            [{"id":"A","filename":"Movie.A.2024.mkv","hash":"h","bytes":1,"host":"rd",
              "progress":100,"status":"downloaded","added":"2024-01-01T00:00:00Z","links":["https://rd/A"]},
             {"id":"B","filename":"Movie.B.2024.mkv","hash":"h","bytes":1,"host":"rd",
              "progress":100,"status":"downloaded","added":"2024-01-01T00:00:00Z","links":["https://rd/B"]}]
            """#
            let infoA = #"{"id":"A","filename":"Movie.A","hash":"h","bytes":1,"progress":100,"status":"downloaded","files":[{"id":1,"path":"/a.mkv","bytes":1,"selected":1}],"links":["https://rd/A"]}"#
            let infoB = #"{"id":"B","filename":"Movie.B","hash":"h","bytes":1,"progress":100,"status":"downloaded","files":[{"id":1,"path":"/b.mkv","bytes":1,"selected":1}],"links":["https://rd/B"]}"#

            MockURLProtocol.handler = { request in
                let url = request.url!.absoluteString
                let json: String
                if url.contains("/torrents/info/A") { json = infoA }
                else if url.contains("/torrents/info/B") { json = infoB }
                else if url.contains("/torrents") { json = listPage1 }   // page 1 (2 < 100 → no page 2)
                else { json = "[]" }
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(json.utf8))
            }

            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            let infos = try await client.allTorrentInfos()
            #expect(infos.count == 2)
            #expect(Set(infos.map(\.id)) == ["A", "B"])   // order not guaranteed (concurrent)
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter TorrentsClientAllInfosTests`
Expected: FAIL — `allTorrentInfos` not defined.

- [ ] **Step 3: Implement `allTorrents` + `allTorrentInfos`**

Add these methods to `TorrentsClient` (after `playableURL(for:)`):
```swift
    /// Every torrent in the library, following RD's pagination (100 per page).
    public func allTorrents(pageSize: Int = 100) async throws -> [Torrent] {
        var all: [Torrent] = []
        var page = 1
        while true {
            let batch = try await torrents(page: page, limit: pageSize)
            all.append(contentsOf: batch)
            if batch.count < pageSize { break }
            page += 1
        }
        return all
    }

    /// Every torrent's detailed info (files + links), fetched concurrently. A torrent whose
    /// info fetch fails is skipped rather than failing the whole load.
    public func allTorrentInfos() async throws -> [TorrentInfo] {
        let torrents = try await allTorrents()
        return await withTaskGroup(of: TorrentInfo?.self) { group in
            for torrent in torrents {
                group.addTask { try? await info(id: torrent.id) }
            }
            var infos: [TorrentInfo] = []
            for await info in group where info != nil { infos.append(info!) }
            return infos
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter TorrentsClientAllInfosTests`
Expected: PASS. Full suite `swift test --package-path Packages/DebridCore` → 58 tests, stable (run twice). Confirm `swift build … | grep -i warning` is empty.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): TorrentsClient.allTorrents + allTorrentInfos (paginated + concurrent fan-out)"
```

---

## Done when

- [ ] `swift test --package-path Packages/DebridCore` green (~58 tests), stable, zero warnings.
- [ ] `DebridCore` exposes: `MediaItem.withMetadata(...)`, `MetadataEnricher` (`enrich(_ item:)`, `enrich(_ items:)`), and `TorrentsClient.allTorrents()` / `allTorrentInfos()`.
- [ ] Enrichment degrades gracefully (a failed/empty lookup leaves the item usable); the batch preserves order; the info fan-out skips failures.
- [ ] No secrets/tokens logged.
- [ ] All work committed.

**The brain, composed (app/integration layer, ~3 lines):**
```swift
let infos   = try await torrentsClient.allTorrentInfos()
let grouped = LibraryBuilder().group(infos)
let library = await MetadataEnricher(tmdb: tmdbClient).enrich(grouped)
```

**Next:** Plan 6 — subtitles (OpenSubtitles) + SwiftData persistence (cache the library + watch progress) + the `VideoPlayerEngine` protocol. Then the Apple TV app.
