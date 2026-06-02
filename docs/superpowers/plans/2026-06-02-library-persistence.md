# Library Persistence (SwiftData cache + WatchProgress) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `DebridCore` an offline-capable, incrementally-refreshed library cache (a Codable `[MediaItem]` snapshot in a file) plus a relational, CloudKit-ready `WatchProgress` store (SwiftData) for Resume / Continue Watching — so the app opens instantly and only genuinely-new content costs a TMDB call.

**Architecture:** Library cache = a file-backed Codable `LibrarySnapshot` (rebuildable, never synced). Watch progress = a SwiftData `@Model` behind a `@ModelActor` store (CloudKit-ready; sync deferred to Stage 3). A pure `LibraryReconciler` decides which freshly-grouped items are already cached (carry their TMDB metadata over) vs new (enrich), keyed by shared RD torrent id. `LibraryService` orchestrates cache-first load + incremental refresh over the existing `TorrentsClient` / `LibraryBuilder` / `MetadataEnricher`.

**Tech Stack:** Swift 6.3 (Swift 6 language mode), SPM, async/await + structured concurrency, **SwiftData** (`@Model` / `@ModelActor` / `ModelContainer` — `DebridCore`'s first dependency, an Apple system framework; package floor macOS 14 already supports it), Swift Testing.

**Design spec:** [`docs/superpowers/specs/2026-06-02-library-persistence-design.md`](../specs/2026-06-02-library-persistence-design.md). First of three Plan 6 slices (persistence → subtitles → `VideoPlayerEngine`).

> **Conventions (keep doing these):** failing test → minimal impl → green → commit; small atomic `feat(core):`/`test(core):`/`fix(core):`/`docs:` commits. Swift 6 value types + `Sendable`; immutable `let` on models; `public` memberwise inits. **Zero warnings** (`swift build --package-path Packages/DebridCore 2>&1 | grep -i warning` prints nothing). Run the **full** suite before each commit (`swift test --package-path Packages/DebridCore`). Any suite touching `MockURLProtocol` MUST nest under the serialized `MockTests` parent. Never log RD tokens / unrestricted URLs (storing `restrictedLink` in the local cache is fine — just don't log it). Do **not** push (owner pushes after review).

**Baseline:** 60 tests green on `main`. Each task adds tests; the running totals below assume tasks land in order.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/DebridCore/Library/MediaItem.swift` (modify) | Add `Codable` to `MediaSource`/`Episode`/`Season`/`MediaItem` (`MediaKind` already is) |
| `Sources/DebridCore/Metadata/ParsedRelease.swift` (modify) | Add `Codable` to `ParsedRelease` |
| `Sources/DebridCore/Persistence/LibrarySnapshot.swift` | The Codable snapshot value type (`schemaVersion`, `builtAt`, `items`) |
| `Sources/DebridCore/Persistence/LibrarySnapshotStore.swift` | File-backed save/load (atomic; `nil` on missing/corrupt/version-mismatch) |
| `Sources/DebridCore/Persistence/WatchProgress.swift` | `@Model WatchProgress`, `WatchState` DTO, `WatchKey` derivation |
| `Sources/DebridCore/Persistence/WatchProgressStore.swift` | `@ModelActor` store: `record` / `progress(forContentKey:)` / `recentlyWatched` |
| `Sources/DebridCore/Library/LibraryReconciler.swift` | Pure: torrent-id delta + split fresh items into carried-over vs new |
| `Sources/DebridCore/Library/LibraryService.swift` | Cache-first `loadCached()` + incremental `refresh()` |
| `Tests/DebridCoreTests/…` | One test file per component (paths in each task) |

---

## Task 1: Codable conformance for the domain value types

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Metadata/ParsedRelease.swift`
- Modify: `Packages/DebridCore/Sources/DebridCore/Library/MediaItem.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/DomainCodableTests.swift`

- [ ] **Step 1: Write the failing test** (pure — plain top-level suite, no network)

`Tests/DebridCoreTests/DomainCodableTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

@Suite struct DomainCodableTests {
    @Test func movieRoundTrips() throws {
        let item = MediaItem(
            id: "movie:tmdb:693134", kind: .movie, title: "Dune: Part Two", year: 2024,
            sources: [MediaSource(torrentID: "T1", fileID: 1, restrictedLink: "https://rd/x",
                                  parsed: ParsedRelease(title: "Dune Part Two", year: 2024,
                                                        resolution: "2160p", videoCodec: "HEVC"))],
            seasons: [], tmdbID: 693134, posterPath: "/p.jpg", overview: "Paul…")
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(MediaItem.self, from: data)
        #expect(decoded == item)
    }

    @Test func showWithSeasonsRoundTrips() throws {
        let ep = Episode(season: 1, number: 2,
                         source: MediaSource(torrentID: "T2", fileID: nil, restrictedLink: "https://rd/y",
                                             parsed: ParsedRelease(title: "Show", season: 1, episode: 2)))
        let item = MediaItem(id: "show:tmdb:1399", kind: .show, title: "Show", year: 2011,
                             sources: [], seasons: [Season(number: 1, episodes: [ep])],
                             tmdbID: 1399, posterPath: "/s.jpg", overview: "o")
        let decoded = try JSONDecoder().decode(MediaItem.self, from: try JSONEncoder().encode(item))
        #expect(decoded == item)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter DomainCodableTests`
Expected: FAIL to **compile** — `MediaItem`/`ParsedRelease` don't conform to `Encodable`/`Decodable`.

- [ ] **Step 3: Add `Codable` conformance**

In `Metadata/ParsedRelease.swift`, change the declaration line:
```swift
public struct ParsedRelease: Sendable, Equatable, Codable {
```
In `Library/MediaItem.swift`, add `Codable` to the four declarations (`MediaKind` already has it):
```swift
public struct MediaSource: Sendable, Equatable, Codable {
```
```swift
public struct Episode: Sendable, Equatable, Identifiable, Codable {
```
```swift
public struct Season: Sendable, Equatable, Identifiable, Codable {
```
```swift
public struct MediaItem: Sendable, Equatable, Identifiable, Codable {
```
(All stored properties are `String`/`Int`/`Bool`/optionals/arrays of already-`Codable` types, so the conformance is synthesized — no `CodingKeys`, no custom methods. `Identifiable`'s `id` is a stored property, so it encodes naturally.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter DomainCodableTests`
Expected: PASS (2 tests). Full suite → 62 tests. Zero warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): Codable conformance for the library domain value types"
```

---

## Task 2: LibrarySnapshot + file-backed LibrarySnapshotStore

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Persistence/LibrarySnapshot.swift`
- Create: `Packages/DebridCore/Sources/DebridCore/Persistence/LibrarySnapshotStore.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/LibrarySnapshotStoreTests.swift`

- [ ] **Step 1: Write the failing test** (pure file I/O in a unique temp dir — plain top-level suite)

`Tests/DebridCoreTests/LibrarySnapshotStoreTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

@Suite struct LibrarySnapshotStoreTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "seret-snap-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func sampleItems() -> [MediaItem] {
        [MediaItem(id: "movie:tmdb:1", kind: .movie, title: "A", year: 2020,
                   sources: [MediaSource(torrentID: "T", fileID: 1, restrictedLink: "https://rd/a",
                                         parsed: ParsedRelease(title: "A"))],
                   seasons: [], tmdbID: 1, posterPath: "/p.jpg", overview: "o")]
    }

    @Test func savesAndLoadsRoundTrip() throws {
        let store = LibrarySnapshotStore(directory: tempDir())
        let snap = LibrarySnapshot(items: sampleItems())
        try store.save(snap)
        let loaded = store.load()
        #expect(loaded?.items == sampleItems())
        #expect(loaded?.schemaVersion == LibrarySnapshot.currentSchemaVersion)
    }

    @Test func loadReturnsNilWhenMissing() {
        #expect(LibrarySnapshotStore(directory: tempDir()).load() == nil)
    }

    @Test func loadReturnsNilOnCorruptData() throws {
        let dir = tempDir()
        let store = LibrarySnapshotStore(directory: dir)
        try Data("not json".utf8).write(to: dir.appending(path: "library.json"))
        #expect(store.load() == nil)
    }

    @Test func loadReturnsNilOnSchemaMismatch() throws {
        let dir = tempDir()
        let store = LibrarySnapshotStore(directory: dir)
        // hand-write a snapshot whose version is in the future
        let future = #"{"schemaVersion":999,"builtAt":0,"items":[]}"#
        try Data(future.utf8).write(to: dir.appending(path: "library.json"))
        #expect(store.load() == nil)
    }

    @Test func saveOverwritesAtomically() throws {
        let store = LibrarySnapshotStore(directory: tempDir())
        try store.save(LibrarySnapshot(items: sampleItems()))
        try store.save(LibrarySnapshot(items: []))     // overwrite
        #expect(store.load()?.items.isEmpty == true)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter LibrarySnapshotStoreTests`
Expected: FAIL to compile — `LibrarySnapshot` / `LibrarySnapshotStore` undefined.

- [ ] **Step 3: Implement the snapshot + store**

`Sources/DebridCore/Persistence/LibrarySnapshot.swift`:
```swift
import Foundation

/// The serializable, offline-capable form of the enriched library. Rebuildable from RD —
/// stored as a device-local file, never CloudKit-synced. Self-sufficient for display and
/// playback (quality lives in `MediaSource.parsed`; the play-time link is `MediaSource.restrictedLink`).
public struct LibrarySnapshot: Sendable, Equatable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let builtAt: Date
    public let items: [MediaItem]

    public init(schemaVersion: Int = LibrarySnapshot.currentSchemaVersion,
                builtAt: Date = Date(), items: [MediaItem]) {
        self.schemaVersion = schemaVersion
        self.builtAt = builtAt
        self.items = items
    }
}
```

`Sources/DebridCore/Persistence/LibrarySnapshotStore.swift`:
```swift
import Foundation

/// Persists the library cache to a single JSON file in `directory`. Reads degrade to `nil`
/// (missing / unreadable / decode failure / schema mismatch) so the caller rebuilds from RD —
/// a bad cache must never crash or surface an error.
public struct LibrarySnapshotStore: Sendable {
    private let directory: URL
    private var fileURL: URL { directory.appending(path: "library.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    public func save(_ snapshot: LibrarySnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)   // write-temp-then-rename
    }

    public func load() -> LibrarySnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data),
              snapshot.schemaVersion == LibrarySnapshot.currentSchemaVersion
        else { return nil }
        return snapshot
    }
}
```
(`builtAt` encodes as a number by default — matches the `"builtAt":0` literal in the schema-mismatch test.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter LibrarySnapshotStoreTests`
Expected: PASS (5 tests). Full suite → 67 tests. Zero warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): LibrarySnapshot + file-backed LibrarySnapshotStore (atomic, degrades to nil)"
```

---

## Task 3: WatchProgress @Model + WatchState DTO + WatchKey derivation

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Persistence/WatchProgress.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/WatchKeyTests.swift`

- [ ] **Step 1: Write the failing test** (pure — key derivation + DTO mapping; no SwiftData context needed)

`Tests/DebridCoreTests/WatchKeyTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

@Suite struct WatchKeyTests {
    private func movie() -> MediaItem {
        MediaItem(id: "movie:tmdb:693134", kind: .movie, title: "Dune", year: 2024,
                  sources: [MediaSource(torrentID: "T1", fileID: 3, restrictedLink: "https://rd/x",
                                        parsed: ParsedRelease(title: "Dune"))],
                  seasons: [], tmdbID: 693134)
    }
    private func show() -> MediaItem {
        let ep = Episode(season: 1, number: 2,
                         source: MediaSource(torrentID: "T2", fileID: nil, restrictedLink: "https://rd/y",
                                             parsed: ParsedRelease(title: "Show", season: 1, episode: 2)))
        return MediaItem(id: "show:tmdb:1399", kind: .show, title: "Show", year: 2011,
                         sources: [], seasons: [Season(number: 1, episodes: [ep])], tmdbID: 1399)
    }

    @Test func movieContentKeyIsTheItemID() {
        #expect(WatchKey.content(forMovie: movie()) == "movie:tmdb:693134")
    }

    @Test func episodeContentKeyPrependsShowID() {
        let ep = show().seasons[0].episodes[0]
        #expect(WatchKey.content(forShow: show(), episode: ep) == "show:tmdb:1399:s1e2")
    }

    @Test func sourceKeyEncodesTorrentAndFile() {
        #expect(WatchKey.source(movie().sources[0]) == "T1#3")
        let noFile = MediaSource(torrentID: "T2", fileID: nil, restrictedLink: "x", parsed: ParsedRelease(title: "y"))
        #expect(WatchKey.source(noFile) == "T2#-")
    }

    @Test func watchStateMapsFromModel() {
        let m = WatchProgress(contentKey: "k", sourceKey: "s", positionSeconds: 12,
                              durationSeconds: 100, finished: false,
                              updatedAt: Date(timeIntervalSince1970: 5))
        let state = WatchState(m)
        #expect(state == WatchState(contentKey: "k", sourceKey: "s", positionSeconds: 12,
                                    durationSeconds: 100, finished: false,
                                    updatedAt: Date(timeIntervalSince1970: 5)))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter WatchKeyTests`
Expected: FAIL to compile — `WatchKey` / `WatchProgress` / `WatchState` undefined.

- [ ] **Step 3: Implement the model, DTO, and key derivation**

`Sources/DebridCore/Persistence/WatchProgress.swift`:
```swift
import Foundation
import SwiftData

/// Per-title playback position. CloudKit-ready (every property defaulted, no unique
/// constraint, no required relationship) so Stage 3 cross-device sync is a config flip.
/// `contentKey` identifies the title (see `WatchKey`); `sourceKey` records the exact file played.
@Model
public final class WatchProgress {
    public var contentKey: String = ""
    public var sourceKey: String = ""
    public var positionSeconds: Double = 0
    public var durationSeconds: Double = 0
    public var finished: Bool = false
    public var updatedAt: Date = Date(timeIntervalSince1970: 0)

    public init(contentKey: String = "", sourceKey: String = "",
                positionSeconds: Double = 0, durationSeconds: Double = 0,
                finished: Bool = false, updatedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.contentKey = contentKey
        self.sourceKey = sourceKey
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.finished = finished
        self.updatedAt = updatedAt
    }
}

/// A `Sendable` snapshot of a `WatchProgress` row — what the store hands back, so callers and
/// tests never touch the (non-`Sendable`) `@Model` class directly.
public struct WatchState: Sendable, Equatable {
    public let contentKey: String
    public let sourceKey: String
    public let positionSeconds: Double
    public let durationSeconds: Double
    public let finished: Bool
    public let updatedAt: Date

    public init(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, updatedAt: Date) {
        self.contentKey = contentKey
        self.sourceKey = sourceKey
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.finished = finished
        self.updatedAt = updatedAt
    }

    public init(_ m: WatchProgress) {
        self.init(contentKey: m.contentKey, sourceKey: m.sourceKey,
                  positionSeconds: m.positionSeconds, durationSeconds: m.durationSeconds,
                  finished: m.finished, updatedAt: m.updatedAt)
    }
}

/// Derives the stable keys used to store/look up watch progress.
public enum WatchKey {
    /// A movie's key is its (TMDB-stable) item id.
    public static func content(forMovie item: MediaItem) -> String { item.id }

    /// An episode's key is the show id + the episode id (`Episode.id` alone, "s1e2", isn't global).
    public static func content(forShow show: MediaItem, episode: Episode) -> String {
        "\(show.id):\(episode.id)"
    }

    /// The exact file played: torrent id + file id (`-` when the torrent is single-file).
    public static func source(_ s: MediaSource) -> String {
        "\(s.torrentID)#\(s.fileID.map(String.init) ?? "-")"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter WatchKeyTests`
Expected: PASS (4 tests). Full suite → 71 tests. Zero warnings. (This is the first `import SwiftData` in the package — confirm it builds clean on the macOS host.)

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): WatchProgress @Model (CloudKit-ready) + WatchState DTO + WatchKey derivation"
```

---

## Task 4: WatchProgressStore (@ModelActor: record / progress / recentlyWatched)

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Persistence/WatchProgressStore.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/WatchProgressStoreTests.swift`

- [ ] **Step 1: Write the failing test** (SwiftData in-memory; pure — no network, plain top-level suite; each test gets a fresh container)

`Tests/DebridCoreTests/WatchProgressStoreTests.swift`:
```swift
import Testing
import Foundation
import SwiftData
@testable import DebridCore

@Suite struct WatchProgressStoreTests {
    private func store() throws -> WatchProgressStore {
        let container = try ModelContainer(
            for: WatchProgress.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return WatchProgressStore(modelContainer: container)
    }

    @Test func recordThenReadRoundTrips() async throws {
        let store = try store()
        try await store.record(contentKey: "movie:tmdb:1", sourceKey: "T1#0",
                               positionSeconds: 42, durationSeconds: 100, finished: false)
        let got = try await store.progress(forContentKey: "movie:tmdb:1")
        #expect(got?.positionSeconds == 42)
        #expect(got?.sourceKey == "T1#0")
        #expect(got?.finished == false)
    }

    @Test func recordUpsertsByContentKey() async throws {
        let store = try store()
        try await store.record(contentKey: "k", sourceKey: "s", positionSeconds: 10,
                               durationSeconds: 100, finished: false)
        try await store.record(contentKey: "k", sourceKey: "s", positionSeconds: 55,
                               durationSeconds: 100, finished: true)
        let got = try await store.progress(forContentKey: "k")
        #expect(got?.positionSeconds == 55)   // updated, not duplicated
        #expect(got?.finished == true)
        #expect(try await store.allCount() == 1)   // exactly one row for the key
    }

    @Test func progressIsNilForUnknownKey() async throws {
        #expect(try await store().progress(forContentKey: "nope") == nil)
    }

    @Test func recentlyWatchedIsUnfinishedWithProgressNewestFirst() async throws {
        let store = try store()
        try await store.record(contentKey: "a", sourceKey: "s", positionSeconds: 10,
                               durationSeconds: 100, finished: false, at: Date(timeIntervalSince1970: 1))
        try await store.record(contentKey: "b", sourceKey: "s", positionSeconds: 20,
                               durationSeconds: 100, finished: false, at: Date(timeIntervalSince1970: 3))
        try await store.record(contentKey: "c", sourceKey: "s", positionSeconds: 99,
                               durationSeconds: 100, finished: true,  at: Date(timeIntervalSince1970: 2)) // finished → excluded
        try await store.record(contentKey: "d", sourceKey: "s", positionSeconds: 0,
                               durationSeconds: 100, finished: false, at: Date(timeIntervalSince1970: 4)) // no progress → excluded
        let recent = try await store.recentlyWatched(limit: 10)
        #expect(recent.map(\.contentKey) == ["b", "a"])   // newest unfinished-with-progress first
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter WatchProgressStoreTests`
Expected: FAIL to compile — `WatchProgressStore` undefined.

- [ ] **Step 3: Implement the store**

`Sources/DebridCore/Persistence/WatchProgressStore.swift`:
```swift
import Foundation
import SwiftData

/// SwiftData-backed watch-progress store. `@ModelActor` owns a `ModelContext` isolated to this
/// actor, so it is safe to use from any task under Swift 6 strict concurrency. Returns `Sendable`
/// `WatchState` values (never the `@Model` across the actor boundary).
@ModelActor
public actor WatchProgressStore {
    /// Most-recent position for a title, or `nil` if never played.
    public func progress(forContentKey key: String) throws -> WatchState? {
        try fetchOne(contentKey: key).map(WatchState.init)
    }

    /// Insert-or-update the single row for `contentKey` (CloudKit forbids a unique constraint,
    /// so we dedupe here). `at` is injectable for deterministic ordering in tests.
    public func record(contentKey: String, sourceKey: String,
                       positionSeconds: Double, durationSeconds: Double,
                       finished: Bool, at: Date = Date()) throws {
        let row = try fetchOne(contentKey: contentKey) ?? {
            let r = WatchProgress(contentKey: contentKey)
            modelContext.insert(r)
            return r
        }()
        row.sourceKey = sourceKey
        row.positionSeconds = positionSeconds
        row.durationSeconds = durationSeconds
        row.finished = finished
        row.updatedAt = at
        try modelContext.save()
    }

    /// Continue-Watching feed: unfinished rows that have progress, newest first.
    public func recentlyWatched(limit: Int) throws -> [WatchState] {
        var descriptor = FetchDescriptor<WatchProgress>(
            predicate: #Predicate { $0.finished == false && $0.positionSeconds > 0 },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(WatchState.init)
    }

    /// Total row count — used by tests to assert upsert (not insert) behavior.
    public func allCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<WatchProgress>())
    }

    private func fetchOne(contentKey key: String) throws -> WatchProgress? {
        var descriptor = FetchDescriptor<WatchProgress>(predicate: #Predicate { $0.contentKey == key })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
```
(`@ModelActor` synthesizes `init(modelContainer:)` and the `modelContext`/`modelExecutor`. Tests construct an in-memory `ModelContainer` and pass it.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter WatchProgressStoreTests`
Expected: PASS (4 tests). Full suite → 75 tests, stable on a second run. Zero warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): WatchProgressStore (@ModelActor) — record/progress/recentlyWatched"
```

---

## Task 5: LibraryReconciler (pure delta + carry-over split)

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Library/LibraryReconciler.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/LibraryReconcilerTests.swift`

- [ ] **Step 1: Write the failing test** (pure — plain top-level suite)

`Tests/DebridCoreTests/LibraryReconcilerTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

@Suite struct LibraryReconcilerTests {
    private func movie(torrent: String, title: String, tmdbID: Int? = nil) -> MediaItem {
        MediaItem(id: tmdbID.map { "movie:tmdb:\($0)" } ?? "movie:\(title)",
                  kind: .movie, title: title, year: 2020,
                  sources: [MediaSource(torrentID: torrent, fileID: 1, restrictedLink: "https://rd/\(torrent)",
                                        parsed: ParsedRelease(title: title))],
                  seasons: [], tmdbID: tmdbID,
                  posterPath: tmdbID == nil ? nil : "/p.jpg",
                  overview: tmdbID == nil ? nil : "o")
    }

    private let r = LibraryReconciler()

    @Test func noDeltaWhenTorrentSetsMatch() {
        let cached = [movie(torrent: "A", title: "A", tmdbID: 1)]
        #expect(r.hasDelta(cached: cached, rdTorrentIDs: ["A"]) == false)
        #expect(r.hasDelta(cached: cached, rdTorrentIDs: ["A", "B"]) == true)
        #expect(r.hasDelta(cached: [], rdTorrentIDs: []) == false)
    }

    @Test func carriesOverKnownItemsAndFlagsNewOnes() {
        let cached = [movie(torrent: "A", title: "A (TMDB)", tmdbID: 1)]      // already enriched
        let fresh  = [movie(torrent: "A", title: "A"),                        // same torrent → known
                      movie(torrent: "B", title: "B")]                        // new torrent → new
        let result = r.reconcile(fresh: fresh, cached: cached)
        #expect(result.count == 2)
        // index 0 carried over with the cached metadata applied to the fresh structure
        guard case .carried(let carried) = result[0] else { Issue.record("expected carried"); return }
        #expect(carried.tmdbID == 1)
        #expect(carried.title == "A (TMDB)")
        #expect(carried.id == "movie:tmdb:1")
        // index 1 flagged for enrichment, untouched
        guard case .needsEnrichment(let fresh1) = result[1] else { Issue.record("expected needsEnrichment"); return }
        #expect(fresh1.tmdbID == nil)
        #expect(fresh1.title == "B")
    }

    @Test func unmatchedCachedItemIsNotCarried() {
        // a cached item whose torrent is no longer present simply doesn't match any fresh item
        let cached = [movie(torrent: "OLD", title: "Gone", tmdbID: 9)]
        let fresh  = [movie(torrent: "NEW", title: "New")]
        let result = r.reconcile(fresh: fresh, cached: cached)
        guard case .needsEnrichment = result[0] else { Issue.record("expected needsEnrichment"); return }
    }

    @Test func knownButUnenrichedCachedItemIsTreatedAsNew() {
        // cached item matched by torrent but never enriched (tmdbID nil) → re-enrich, don't carry junk
        let cached = [movie(torrent: "A", title: "A", tmdbID: nil)]
        let result = r.reconcile(fresh: [movie(torrent: "A", title: "A")], cached: cached)
        guard case .needsEnrichment = result[0] else { Issue.record("expected needsEnrichment"); return }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter LibraryReconcilerTests`
Expected: FAIL to compile — `LibraryReconciler` / `Reconciled` undefined.

- [ ] **Step 3: Implement the reconciler**

`Sources/DebridCore/Library/LibraryReconciler.swift`:
```swift
import Foundation

/// The outcome of reconciling one freshly-grouped item against the cache, in fresh-library order.
public enum Reconciled: Sendable, Equatable {
    case carried(MediaItem)         // content already known + enriched → cached metadata reused
    case needsEnrichment(MediaItem) // genuinely new (or never enriched) → must hit TMDB
}

/// Pure incremental-refresh logic. Identity is by **shared RD torrent id** (stable), so an item
/// already in the cache carries its TMDB metadata over onto the fresh structure (picking up any
/// new episodes), while genuinely-new items are flagged for enrichment. No I/O.
public struct LibraryReconciler: Sendable {
    public init() {}

    /// Every RD torrent id an item draws from (movie sources + every episode's source).
    static func torrentIDs(of item: MediaItem) -> Set<String> {
        var ids = Set(item.sources.map(\.torrentID))
        for season in item.seasons {
            for episode in season.episodes { ids.insert(episode.source.torrentID) }
        }
        return ids
    }

    /// True when RD's current torrent-id set differs from what `cached` was built from.
    public func hasDelta(cached: [MediaItem], rdTorrentIDs: Set<String>) -> Bool {
        let cachedIDs = cached.reduce(into: Set<String>()) { $0.formUnion(Self.torrentIDs(of: $1)) }
        return cachedIDs != rdTorrentIDs
    }

    /// Splits the freshly-grouped library into carried-over (reuse cached TMDB metadata) and
    /// new (enrich) — preserving fresh order so the caller can reassemble after enriching.
    public func reconcile(fresh: [MediaItem], cached: [MediaItem]) -> [Reconciled] {
        var byTorrent: [String: MediaItem] = [:]
        for item in cached {
            for id in Self.torrentIDs(of: item) { byTorrent[id] = item }
        }
        return fresh.map { item in
            let match = Self.torrentIDs(of: item).lazy.compactMap { byTorrent[$0] }.first
            if let match, match.tmdbID != nil {
                return .carried(item.withMetadata(tmdbID: match.tmdbID, title: match.title,
                                                  posterPath: match.posterPath, overview: match.overview))
            }
            return .needsEnrichment(item)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter LibraryReconcilerTests`
Expected: PASS (4 tests). Full suite → 79 tests. Zero warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): LibraryReconciler — pure torrent-id delta + carry-over split"
```

---

## Task 6: LibraryService (cache-first load + incremental refresh)

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Library/LibraryService.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/LibraryServiceTests.swift`

**Context:** `LibraryService` orchestrates the existing pieces. `refresh()` first lists RD torrents cheaply (`TorrentsClient.allTorrents()` → ids); if the id set matches the cache it returns the cache untouched (no info fetches, no TMDB). On a delta it fetches infos (`allTorrentInfos()`), groups (`LibraryBuilder.group`), reconciles (Task 5), enriches **only** the new items (`MetadataEnricher.enrich(_:)`), reassembles in order, writes a fresh snapshot, and returns. Tests drive it through `MockURLProtocol` routing RD **and** TMDB — so the suite nests under the serialized `MockTests` parent.

- [ ] **Step 1: Write the failing test** (nested under `MockTests`; routes RD + TMDB by URL; a temp-dir snapshot store)

`Tests/DebridCoreTests/LibraryServiceTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct LibraryServiceTests {
        init() { MockURLProtocol.handler = nil }

        struct StubTokens: AccessTokenProviding {
            func validAccessToken() async throws -> String { "TESTTOKEN" }
        }

        private func tempDir() -> URL {
            let dir = FileManager.default.temporaryDirectory.appending(path: "seret-svc-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }

        private func service(directory: URL) -> LibraryService {
            let http = HTTPClient(session: .mock)
            return LibraryService(
                torrents: TorrentsClient(http: http, tokens: StubTokens()),
                builder: LibraryBuilder(),
                enricher: MetadataEnricher(tmdb: TMDBClient(apiKey: "K", http: http)),
                store: LibrarySnapshotStore(directory: directory))
        }

        // --- static response builders: the handler captures NOTHING (no self, no mutable var),
        //     so it stays @Sendable-safe under Swift 6. Two-pass tests reassign the handler
        //     between (sequential) refresh awaits rather than mutating captured state. ---
        private static func torrentListJSON(_ ids: [String]) -> String {
            let rows = ids.map { #"{"id":"\#($0)","filename":"\#($0).2024.1080p.mkv","hash":"h","bytes":1,"host":"rd","progress":100,"status":"downloaded","added":"2024-01-01T00:00:00Z","links":["https://rd/\#($0)"]}"# }
            return "[\(rows.joined(separator: ","))]"
        }
        private static func infoJSON(_ id: String, release: String) -> String {
            #"{"id":"\#(id)","filename":"\#(release)","hash":"h","bytes":1,"progress":100,"status":"downloaded","files":[{"id":1,"path":"/\#(release)","bytes":1,"selected":1}],"links":["https://rd/\#(id)"]}"#
        }
        private static func tmdbJSON(id: Int, title: String) -> String {
            #"{"results":[{"id":\#(id),"title":"\#(title)","release_date":"2024-01-01","poster_path":"/p.jpg","overview":"o"}]}"#
        }
        private static func resp(_ req: URLRequest, _ status: Int, _ json: String) -> (HTTPURLResponse, Data) {
            (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }

        @Test func coldRefreshBuildsEnrichesAndPersists() async throws {
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/torrents/info/A") { return Self.resp(req, 200, Self.infoJSON("A", release: "Alpha.2024.1080p.mkv")) }
                if url.contains("/torrents")        { return Self.resp(req, 200, Self.torrentListJSON(["A"])) }
                if url.contains("/search/movie")    { return Self.resp(req, 200, Self.tmdbJSON(id: 111, title: "Alpha")) }
                return Self.resp(req, 200, "[]")
            }
            let svc = service(directory: tempDir())
            #expect(svc.loadCached() == nil)                  // nothing yet

            let library = try await svc.refresh()
            #expect(library.count == 1)
            #expect(library[0].tmdbID == 111)
            #expect(library[0].title == "Alpha")
            #expect(svc.loadCached()?.first?.tmdbID == 111)   // persisted for next launch
        }

        @Test func unchangedRefreshReusesCacheWithoutTMDB() async throws {
            let svc = service(directory: tempDir())
            // 1st pass: enrich A from TMDB.
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/torrents/info/A") { return Self.resp(req, 200, Self.infoJSON("A", release: "Alpha.2024.1080p.mkv")) }
                if url.contains("/torrents")        { return Self.resp(req, 200, Self.torrentListJSON(["A"])) }
                if url.contains("/search/movie")    { return Self.resp(req, 200, Self.tmdbJSON(id: 111, title: "Alpha")) }
                return Self.resp(req, 200, "[]")
            }
            _ = try await svc.refresh()
            // 2nd pass: same torrents, but TMDB now 500s. If A were re-enriched the 500 would strip
            // its metadata; carrying the cache over means it stays enriched (TMDB not called).
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/torrents/info/A") { return Self.resp(req, 200, Self.infoJSON("A", release: "Alpha.2024.1080p.mkv")) }
                if url.contains("/torrents")        { return Self.resp(req, 200, Self.torrentListJSON(["A"])) }
                if url.contains("/search/movie")    { return Self.resp(req, 500, "{}") }
                return Self.resp(req, 200, "[]")
            }
            let library = try await svc.refresh()
            #expect(library.count == 1)
            #expect(library[0].tmdbID == 111)
        }

        @Test func deltaEnrichesOnlyNewItems() async throws {
            let svc = service(directory: tempDir())
            // 1st pass: [A] → A enriched to 111.
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/torrents/info/A") { return Self.resp(req, 200, Self.infoJSON("A", release: "Alpha.2024.1080p.mkv")) }
                if url.contains("/torrents")        { return Self.resp(req, 200, Self.torrentListJSON(["A"])) }
                if url.contains("/search/movie")    { return Self.resp(req, 200, Self.tmdbJSON(id: 111, title: "Alpha")) }
                return Self.resp(req, 200, "[]")
            }
            _ = try await svc.refresh()
            // 2nd pass: [A,B]. Alpha would now return 999 (proves A is NOT re-queried); Beta → 222.
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/torrents/info/A") { return Self.resp(req, 200, Self.infoJSON("A", release: "Alpha.2024.1080p.mkv")) }
                if url.contains("/torrents/info/B") { return Self.resp(req, 200, Self.infoJSON("B", release: "Beta.2024.1080p.mkv")) }
                if url.contains("/torrents")        { return Self.resp(req, 200, Self.torrentListJSON(["A", "B"])) }
                if url.contains("/search/movie") {
                    if req.url!.absoluteString.contains("query=Beta") { return Self.resp(req, 200, Self.tmdbJSON(id: 222, title: "Beta")) }
                    return Self.resp(req, 200, Self.tmdbJSON(id: 999, title: "Alpha"))
                }
                return Self.resp(req, 200, "[]")
            }
            let library = try await svc.refresh()
            #expect(Set(library.compactMap(\.tmdbID)) == [111, 222])   // A kept 111 (carried), B got 222 (new)
        }

        @Test func refreshFailureLeavesCacheReadable() async throws {
            let svc = service(directory: tempDir())
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/torrents/info/A") { return Self.resp(req, 200, Self.infoJSON("A", release: "Alpha.2024.1080p.mkv")) }
                if url.contains("/torrents")        { return Self.resp(req, 200, Self.torrentListJSON(["A"])) }
                if url.contains("/search/movie")    { return Self.resp(req, 200, Self.tmdbJSON(id: 111, title: "Alpha")) }
                return Self.resp(req, 200, "[]")
            }
            _ = try await svc.refresh()
            // now every RD call 500s → refresh throws, but the cache still loads
            MockURLProtocol.handler = { req in Self.resp(req, 500, "{}") }
            await #expect(throws: (any Error).self) { try await svc.refresh() }
            #expect(svc.loadCached()?.first?.tmdbID == 111)
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter LibraryServiceTests`
Expected: FAIL to compile — `LibraryService` undefined.

- [ ] **Step 3: Implement LibraryService**

`Sources/DebridCore/Library/LibraryService.swift`:
```swift
import Foundation

/// The brain's top-level library API: load the cached library instantly (offline-capable),
/// and refresh it against Real-Debrid incrementally — only genuinely-new content costs a TMDB call.
public struct LibraryService: Sendable {
    private let torrents: TorrentsClient
    private let builder: LibraryBuilder
    private let enricher: MetadataEnricher
    private let store: LibrarySnapshotStore
    private let reconciler: LibraryReconciler

    public init(torrents: TorrentsClient, builder: LibraryBuilder,
                enricher: MetadataEnricher, store: LibrarySnapshotStore,
                reconciler: LibraryReconciler = LibraryReconciler()) {
        self.torrents = torrents
        self.builder = builder
        self.enricher = enricher
        self.store = store
        self.reconciler = reconciler
    }

    /// The last persisted library, decoded from disk. Instant and offline; `nil` on first run
    /// or an unreadable cache.
    public func loadCached() -> [MediaItem]? {
        store.load()?.items
    }

    /// Reconcile the cache against RD. Cheap when nothing changed (one torrent-list call); on a
    /// delta, re-groups and enriches only new items, then persists. Throws on RD/network failure
    /// (the caller keeps showing `loadCached()`).
    @discardableResult
    public func refresh() async throws -> [MediaItem] {
        let cached = loadCached() ?? []
        let rdTorrentIDs = Set(try await torrents.allTorrents().map(\.id))
        guard reconciler.hasDelta(cached: cached, rdTorrentIDs: rdTorrentIDs) else {
            return cached
        }

        let infos = try await torrents.allTorrentInfos()
        let fresh = builder.group(infos)
        let plan = reconciler.reconcile(fresh: fresh, cached: cached)

        let toEnrich = plan.compactMap { step -> MediaItem? in
            if case .needsEnrichment(let item) = step { return item } else { return nil }
        }
        let enriched = await enricher.enrich(toEnrich)

        var enrichedIterator = enriched.makeIterator()
        let library = plan.map { step -> MediaItem in
            switch step {
            case .carried(let item): return item
            case .needsEnrichment: return enrichedIterator.next() ?? MediaItem(
                id: "", kind: .movie, title: "", year: nil, sources: [], seasons: [])
            }
        }

        try store.save(LibrarySnapshot(items: library))
        return library
    }
}
```
(The `?? MediaItem(...)` fallback is unreachable — `enriched.count` equals the `.needsEnrichment` count and order is preserved by `MetadataEnricher.enrich(_:)` — but it keeps the map total without a force-unwrap. The grouping/enrichment order is preserved end-to-end, so `library` is in fresh-library order.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter LibraryServiceTests`
Expected: PASS (4 tests). Then the FULL suite → **83 tests**, run **twice** for concurrency stability. Zero warnings (`swift build --package-path Packages/DebridCore 2>&1 | grep -i warning` prints nothing).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): LibraryService — cache-first load + incremental refresh (enrich only new)"
```

---

## Task 7: Reconcile the design spec (documentation)

**Files:**
- Modify: `docs/superpowers/specs/2026-06-02-seret-design.md`

> No test — documentation only. Keep the north-star spec consistent with what was built.

- [ ] **Step 1: Patch §5.5** "Library & Persistence (SwiftData)" to reflect the hybrid model: the library cache is a Codable **`LibrarySnapshot`** file (not relational `@Model`s), and **`WatchProgress` is the single relational `@Model`** (CloudKit-ready). Note the code uses **`MediaSource`** where the spec said "`MediaFile`", and point to [`2026-06-02-library-persistence-design.md`](docs/superpowers/specs/2026-06-02-library-persistence-design.md) for the detailed design. Leave the `WatchProgress` row description intact.

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-06-02-seret-design.md
git commit -m "docs(spec): reconcile §5.5 with the as-built hybrid persistence (snapshot + WatchProgress @Model)"
```

---

## Done when

- [ ] `swift test --package-path Packages/DebridCore` green (**83 tests**), stable across two runs, zero warnings.
- [ ] `DebridCore` exposes: `LibrarySnapshot` + `LibrarySnapshotStore` (file cache), `WatchProgress` `@Model` + `WatchState` + `WatchKey` + `WatchProgressStore` (record/progress/recentlyWatched), `LibraryReconciler`, and `LibraryService` (`loadCached()` + `refresh()`).
- [ ] Cache-first works (`loadCached()` returns the persisted library offline); refresh is incremental (unchanged → no TMDB; delta → only new items enriched; removed torrents drop out); a refresh failure leaves the cache readable.
- [ ] `WatchProgress` is CloudKit-shaped (all props defaulted, no unique constraint) — sync still off.
- [ ] No tokens / unrestricted URLs logged. Spec §5.5 reconciled. All work committed (not pushed).

> **Consumer-side (Plan 7, not this slice):** two §6 behaviors live where the app wires things up — swallowing `WatchProgressStore.record` errors during playback, and degrading to a no-progress mode if the SwiftData `ModelContainer` can't initialize. `DebridCore` here just surfaces throwing APIs (the testable choice); the app decides to ignore/degrade.

**Next Plan 6 slices:** subtitles (`SubtitleProvider` + `OpenSubtitlesProvider`), then the `VideoPlayerEngine` protocol. Then Plan 7 (the Apple TV app) consumes `LibraryService` + `WatchProgressStore`.
