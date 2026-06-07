# Remove from Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user permanently remove a movie/show from their library — deleting every Real-Debrid torrent backing it — from both the poster grid and the detail screen, on tvOS and iOS.

**Architecture:** Deletion logic lives in DebridCore (`LibraryService.remove`, idempotent on 404). `LibraryStore.remove` (DebridUI) is the single orchestration point: it calls the service, purges watch progress, and drops the item from in-memory state optimistically. Both apps surface the action via a confirmation-gated context menu (grid) and detail-screen control, calling that one store method.

**Tech Stack:** Swift 6 / SwiftUI, SwiftData (watch progress), SwiftPM packages (DebridCore, DebridUI) tested host-free with `swift test`; apps built with `xcodebuild`. Swift Testing (`@Test`/`#expect`).

**Branch:** `feat/stage2-search-add` (current). Stage only the paths each task names — never `git add -A` (owner may be editing in parallel; there is also a pre-existing uncommitted change in `TMDBClient.swift` that must stay out of these commits).

**Spec:** `docs/superpowers/specs/2026-06-07-remove-from-library-design.md`

---

## File Structure

**DebridCore (brain):**
- Modify `Packages/DebridCore/Sources/DebridCore/Library/LibraryService.swift` — add `remove(_:)` + `torrentIDs(for:)`.
- Modify `Packages/DebridCore/Sources/DebridCore/Persistence/WatchProgressStore.swift` — add `deleteProgress(forContentKeys:)`.
- Test `Packages/DebridCore/Tests/DebridCoreTests/LibraryServiceRemoveTests.swift` (new).
- Test `Packages/DebridCore/Tests/DebridCoreTests/WatchProgressDeleteTests.swift` (new).

**DebridUI (shared view-models/seams):**
- Modify `Shared/DebridUI/Sources/DebridUI/Library/LibraryProviding.swift` — add `remove(_:)` to the seam.
- Modify `Shared/DebridUI/Sources/DebridUI/Detail/WatchProgressProviding.swift` — add `deleteProgress(forContentKeys:)` to the seam.
- Modify `Shared/DebridUI/Sources/DebridUI/Library/LibraryStore.swift` — add `Removal` state, `remove(_:)`, `clearRemovalError()`, watch injection.
- Modify `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift` — build watch store before `LibraryStore`, inject it.
- Test `Shared/DebridUI/Tests/DebridUITests/LibraryStoreRemoveTests.swift` (new).
- Modify the two existing watch fakes so they still conform: `Tests/DebridUITests/HomeStoreTests.swift`, `Tests/DebridUITests/DetailStoreTests.swift`. Modify `Tests/DebridUITests/LibraryStoreTests.swift`'s `FakeLibrary`.

**iOS app (SeretMobile):**
- Modify `Apps/SeretMobile/Detail/DetailScreen.swift` — overflow menu + confirm + dismiss/alert.
- Modify `Apps/SeretMobile/Library/LibraryGrid.swift` — `onRemove` + context menu.
- Modify `Apps/SeretMobile/Library/MyLibraryScreen.swift` — confirm dialog + call `store.remove` + error alert.

**tvOS app (SeretTV):**
- Modify `Apps/SeretTV/Detail/DetailView.swift` — owns confirm/dismiss; passes `onRemove` down.
- Modify `Apps/SeretTV/Detail/MovieDetailView.swift` and `Apps/SeretTV/Detail/ShowDetailView.swift` — `onRemove` param + Remove button.
- Modify `Apps/SeretTV/Library/PosterCard.swift`, `PosterGrid.swift`, `LibraryScreen.swift` — thread `onRemove` + context menu.
- Modify `Apps/SeretTV/Library/MyLibraryScreen.swift` — confirm dialog + call `store.remove` + error alert.

---

## Task 1: DebridCore — `LibraryService.remove`

**Files:**
- Test: `Packages/DebridCore/Tests/DebridCoreTests/LibraryServiceRemoveTests.swift` (create)
- Modify: `Packages/DebridCore/Sources/DebridCore/Library/LibraryService.swift`
- Modify: `Shared/DebridUI/Sources/DebridUI/Library/LibraryProviding.swift` (seam — keeps `LibraryService: LibraryProviding` valid)

- [ ] **Step 1: Write the failing test**

Create `Packages/DebridCore/Tests/DebridCoreTests/LibraryServiceRemoveTests.swift`. This mirrors `LibraryServiceTests.swift`'s `MockURLProtocol` pattern.

```swift
import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct LibraryServiceRemoveTests {
        init() { MockURLProtocol.handler = nil }

        struct StubTokens: AccessTokenProviding {
            func validAccessToken() async throws -> String { "TESTTOKEN" }
        }

        private func tempDir() -> URL {
            let dir = FileManager.default.temporaryDirectory.appending(path: "seret-rm-\(UUID().uuidString)")
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

        private func src(_ torrentID: String) -> MediaSource {
            MediaSource(torrentID: torrentID, fileID: nil, restrictedLink: "https://rd/\(torrentID)",
                        parsed: ParsedRelease(title: "x"))
        }
        private func movie(_ id: String, torrents ids: [String]) -> MediaItem {
            MediaItem(id: id, kind: .movie, title: "M \(id)", year: 2024,
                      sources: ids.map(src), seasons: [])
        }
        private func resp(_ req: URLRequest, _ status: Int) -> (HTTPURLResponse, Data) {
            (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data())
        }

        @Test func deletesAllTorrentsForAMovieAndDropsFromSnapshot() async throws {
            let dir = tempDir()
            let svc = service(directory: dir)
            // Seed a snapshot with two items; remove one (it has two source torrents).
            try LibrarySnapshotStore(directory: dir).save(
                LibrarySnapshot(items: [movie("keep", torrents: ["K1"]),
                                        movie("gone", torrents: ["A", "B"])]))
            var deleted: [String] = []
            // Capturing a local array in @Sendable closure: use a class box for thread-safety.
            let box = DeletedBox()
            MockURLProtocol.handler = { req in
                if req.httpMethod == "DELETE" { box.append(req.url!.lastPathComponent) }
                return Self.resp200(req)
            }
            try await svc.remove(movie("gone", torrents: ["A", "B"]))
            deleted = box.values
            #expect(Set(deleted) == ["A", "B"])
            #expect(svc.loadCached()?.map(\.id) == ["keep"])
        }

        @Test func treats404AsSuccess() async throws {
            let dir = tempDir()
            let svc = service(directory: dir)
            try LibrarySnapshotStore(directory: dir).save(
                LibrarySnapshot(items: [movie("gone", torrents: ["A"])]))
            MockURLProtocol.handler = { req in
                (HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
            try await svc.remove(movie("gone", torrents: ["A"]))   // must NOT throw
            #expect(svc.loadCached()?.isEmpty == true)
        }

        @Test func nonNotFoundFailureThrowsAndPreservesSnapshot() async throws {
            let dir = tempDir()
            let svc = service(directory: dir)
            try LibrarySnapshotStore(directory: dir).save(
                LibrarySnapshot(items: [movie("gone", torrents: ["A"])]))
            MockURLProtocol.handler = { req in
                (HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
            }
            await #expect(throws: (any Error).self) {
                try await svc.remove(movie("gone", torrents: ["A"]))
            }
            #expect(svc.loadCached()?.map(\.id) == ["gone"])   // snapshot untouched
        }

        private static func resp200(_ req: URLRequest) -> (HTTPURLResponse, Data) {
            (HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }
    }
}

/// Thread-safe recorder for DELETE paths captured inside the @Sendable mock handler.
private final class DeletedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [String] = []
    func append(_ s: String) { lock.lock(); _values.append(s); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return _values }
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `cd Packages/DebridCore && swift test --filter LibraryServiceRemoveTests`
Expected: FAIL — `value of type 'LibraryService' has no member 'remove'`.

- [ ] **Step 3: Implement `remove` + `torrentIDs`**

In `Packages/DebridCore/Sources/DebridCore/Library/LibraryService.swift`, add inside the `LibraryService` struct (after `refresh()`):

```swift
    /// Permanently delete an item from Real-Debrid: removes every torrent backing it, then drops
    /// it from the persisted snapshot. Idempotent — a `404` (torrent already gone) counts as
    /// success. Any other RD/network failure throws WITHOUT rewriting the snapshot, so the next
    /// `refresh()` reconciles the UI to reality.
    public func remove(_ item: MediaItem) async throws {
        for id in Self.torrentIDs(for: item) {
            do {
                try await torrents.deleteTorrent(id: id)
            } catch HTTPError.status(let code, _) where code == 404 {
                continue   // already deleted — treat as success
            }
        }
        let remaining = (store.load()?.items ?? []).filter { $0.id != item.id }
        try store.save(LibrarySnapshot(items: remaining))
    }

    /// The unique set of RD torrent ids backing an item: a movie's source torrents, or every
    /// episode's source torrent for a show (season packs collapse to one id).
    static func torrentIDs(for item: MediaItem) -> [String] {
        switch item.kind {
        case .movie:
            return Array(Set(item.sources.map(\.torrentID)))
        case .show:
            return Array(Set(item.seasons.flatMap { $0.episodes.map(\.source.torrentID) }))
        }
    }
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `cd Packages/DebridCore && swift test --filter LibraryServiceRemoveTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Extend the `LibraryProviding` seam so DebridUI compiles later**

In `Shared/DebridUI/Sources/DebridUI/Library/LibraryProviding.swift`, add the requirement to the protocol (the empty `extension LibraryService: LibraryProviding {}` now picks up the new `remove(_:)` automatically):

```swift
public protocol LibraryProviding: Sendable {
    func loadCached() -> [MediaItem]?
    func refresh() async throws -> [MediaItem]
    func remove(_ item: MediaItem) async throws
}
```

(No DebridUI build yet — `swift test` for DebridUI happens in Task 3. This step only edits the protocol so the package compiles once `LibraryStore` uses it.)

- [ ] **Step 6: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Library/LibraryService.swift \
        Packages/DebridCore/Tests/DebridCoreTests/LibraryServiceRemoveTests.swift \
        Shared/DebridUI/Sources/DebridUI/Library/LibraryProviding.swift
git commit -m "feat(core): LibraryService.remove deletes RD torrents + drops from snapshot"
```

---

## Task 2: DebridCore — `WatchProgressStore.deleteProgress`

**Files:**
- Test: `Packages/DebridCore/Tests/DebridCoreTests/WatchProgressDeleteTests.swift` (create)
- Modify: `Packages/DebridCore/Sources/DebridCore/Persistence/WatchProgressStore.swift`

- [ ] **Step 1: Write the failing test**

Create `Packages/DebridCore/Tests/DebridCoreTests/WatchProgressDeleteTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import DebridCore

@Suite struct WatchProgressDeleteTests {
    private func store() throws -> WatchProgressStore {
        let container = try ModelContainer(
            for: WatchProgress.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return WatchProgressStore(modelContainer: container)
    }

    @Test func deletesOnlyTheGivenKeys() async throws {
        let s = try store()
        try await s.record(contentKey: "movie:a", sourceKey: "t#-", positionSeconds: 10,
                           durationSeconds: 100, finished: false)
        try await s.record(contentKey: "show:x:s1e1", sourceKey: "t#-", positionSeconds: 5,
                           durationSeconds: 100, finished: false)
        try await s.record(contentKey: "movie:keep", sourceKey: "t#-", positionSeconds: 7,
                           durationSeconds: 100, finished: false)

        try await s.deleteProgress(forContentKeys: ["movie:a", "show:x:s1e1"])

        #expect(try await s.progress(forContentKey: "movie:a") == nil)
        #expect(try await s.progress(forContentKey: "show:x:s1e1") == nil)
        #expect(try await s.progress(forContentKey: "movie:keep") != nil)
    }

    @Test func emptyKeysIsANoOp() async throws {
        let s = try store()
        try await s.record(contentKey: "movie:a", sourceKey: "t#-", positionSeconds: 10,
                           durationSeconds: 100, finished: false)
        try await s.deleteProgress(forContentKeys: [])
        #expect(try await s.progress(forContentKey: "movie:a") != nil)
    }
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `cd Packages/DebridCore && swift test --filter WatchProgressDeleteTests`
Expected: FAIL — no member `deleteProgress`.

- [ ] **Step 3: Implement `deleteProgress`**

In `Packages/DebridCore/Sources/DebridCore/Persistence/WatchProgressStore.swift`, add inside the actor (after `recentlyWatched`):

```swift
    /// Delete the rows for these content keys (used when an item is removed from the library).
    /// No-op for an empty list.
    public func deleteProgress(forContentKeys keys: [String]) throws {
        guard !keys.isEmpty else { return }
        let rows = try modelContext.fetch(FetchDescriptor<WatchProgress>(
            predicate: #Predicate { keys.contains($0.contentKey) }))
        for row in rows { modelContext.delete(row) }
        try modelContext.save()
    }
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `cd Packages/DebridCore && swift test --filter WatchProgressDeleteTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Run the whole DebridCore suite (no regressions)**

Run: `cd Packages/DebridCore && swift test`
Expected: PASS, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Persistence/WatchProgressStore.swift \
        Packages/DebridCore/Tests/DebridCoreTests/WatchProgressDeleteTests.swift
git commit -m "feat(core): WatchProgressStore.deleteProgress(forContentKeys:)"
```

---

## Task 3: DebridUI — `LibraryStore.remove` + seam + watch injection

**Files:**
- Modify: `Shared/DebridUI/Sources/DebridUI/Detail/WatchProgressProviding.swift`
- Modify: `Shared/DebridUI/Sources/DebridUI/Library/LibraryStore.swift`
- Modify (keep conformers compiling): `Shared/DebridUI/Tests/DebridUITests/LibraryStoreTests.swift`, `HomeStoreTests.swift`, `DetailStoreTests.swift`
- Test: `Shared/DebridUI/Tests/DebridUITests/LibraryStoreRemoveTests.swift` (create)

- [ ] **Step 1: Extend the `WatchProgressProviding` seam**

In `Shared/DebridUI/Sources/DebridUI/Detail/WatchProgressProviding.swift`, add the requirement to the protocol. `WatchProgressStore` already satisfies it (the new actor method from Task 2 is the async witness — no extension change needed):

```swift
public protocol WatchProgressProviding: Sendable {
    func progress(forContentKey key: String) async throws -> WatchState?
    func record(contentKey: String, sourceKey: String,
                positionSeconds: Double, durationSeconds: Double, finished: Bool) async throws
    /// Continue-Watching feed: unfinished rows with progress, newest first.
    func recentlyWatched(limit: Int) async throws -> [WatchState]
    /// Delete progress rows for the given content keys (item removed from library).
    func deleteProgress(forContentKeys keys: [String]) async throws
}
```

- [ ] **Step 2: Update the two existing watch fakes so the package tests still compile**

In `Shared/DebridUI/Tests/DebridUITests/HomeStoreTests.swift`, add to `FakeWatch`:

```swift
    func deleteProgress(forContentKeys keys: [String]) async throws {}
```

In `Shared/DebridUI/Tests/DebridUITests/DetailStoreTests.swift`, add to the `FakeWatch` actor:

```swift
    func deleteProgress(forContentKeys keys: [String]) async throws {
        for k in keys { rows[k] = nil }
    }
```

- [ ] **Step 3: Update `FakeLibrary` in the existing LibraryStore tests**

In `Shared/DebridUI/Tests/DebridUITests/LibraryStoreTests.swift`, add to `FakeLibrary`:

```swift
    func remove(_ item: MediaItem) async throws {}
```

- [ ] **Step 4: Write the failing remove test**

Create `Shared/DebridUI/Tests/DebridUITests/LibraryStoreRemoveTests.swift`:

```swift
import Testing
import Foundation
import DebridCore
@testable import DebridUI

private func movie(_ id: String) -> MediaItem {
    MediaItem(id: id, kind: .movie, title: "Movie \(id)", year: 2024, sources: [], seasons: [])
}
private func showWithEpisodes(_ id: String) -> MediaItem {
    let ep = Episode(season: 1, number: 1,
                     source: MediaSource(torrentID: "t", fileID: nil, restrictedLink: "l",
                                         parsed: ParsedRelease(title: "x")))
    return MediaItem(id: id, kind: .show, title: "Show \(id)", year: 2023,
                     sources: [], seasons: [Season(number: 1, episodes: [ep])])
}

private enum FakeError: Error { case boom }

private final class RemoveFakeLibrary: LibraryProviding {
    let cached: [MediaItem]
    let removeError: FakeError?
    init(cached: [MediaItem], removeError: FakeError? = nil) {
        self.cached = cached; self.removeError = removeError
    }
    func loadCached() -> [MediaItem]? { cached }
    func refresh() async throws -> [MediaItem] { cached }
    func remove(_ item: MediaItem) async throws { if let e = removeError { throw e } }
}

private actor RecordingWatch: WatchProgressProviding {
    private(set) var deletedKeys: [String] = []
    func progress(forContentKey key: String) async throws -> WatchState? { nil }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool) async throws {}
    func recentlyWatched(limit: Int) async throws -> [WatchState] { [] }
    func deleteProgress(forContentKeys keys: [String]) async throws { deletedKeys.append(contentsOf: keys) }
}

@MainActor
@Suite struct LibraryStoreRemoveTests {
    @Test func successDropsItemAndPurgesWatchProgress() async {
        let watch = RecordingWatch()
        let store = LibraryStore(
            library: RemoveFakeLibrary(cached: [movie("1"), showWithEpisodes("2")]),
            watch: watch)
        await store.load()
        #expect(store.movies.count == 1 && store.shows.count == 1)

        await store.remove(store.movies[0])
        #expect(store.movies.isEmpty)
        #expect(store.removal == .idle)
        #expect(await watch.deletedKeys == ["1"])   // movie content key == item id
    }

    @Test func removingAShowPurgesEpisodeKeys() async {
        let watch = RecordingWatch()
        let store = LibraryStore(library: RemoveFakeLibrary(cached: [showWithEpisodes("2")]), watch: watch)
        await store.load()
        await store.remove(store.shows[0])
        #expect(store.shows.isEmpty)
        #expect(await watch.deletedKeys == ["2:s1e1"])   // WatchKey.content(forShow:episode:)
    }

    @Test func failureSetsErrorAndKeepsItem() async {
        let store = LibraryStore(
            library: RemoveFakeLibrary(cached: [movie("1")], removeError: .boom), watch: RecordingWatch())
        await store.load()
        await store.remove(store.movies[0])
        #expect(store.movies.count == 1)            // item retained on failure
        guard case .failed = store.removal else {
            #expect(Bool(false), "expected .failed, got \(store.removal)"); return
        }
        store.clearRemovalError()
        #expect(store.removal == .idle)
    }
}
```

- [ ] **Step 5: Run the test, verify it fails**

Run: `cd Shared/DebridUI && swift test --filter LibraryStoreRemoveTests`
Expected: FAIL — `LibraryStore` has no `remove`/`removal`/`clearRemovalError`, and `init` has no `watch:`.

- [ ] **Step 6: Implement remove + state + watch injection in `LibraryStore`**

In `Shared/DebridUI/Sources/DebridUI/Library/LibraryStore.swift`:

Replace the stored deps + init:

```swift
    private let library: LibraryProviding
    private let watch: WatchProgressProviding?

    public init(library: LibraryProviding, watch: WatchProgressProviding? = nil) {
        self.library = library
        self.watch = watch
    }
```

Add the removal state next to the other published properties (after `attempt`):

```swift
    public enum Removal: Equatable { case idle, removing(MediaItem), failed(String) }
    public private(set) var removal: Removal = .idle
```

Add these methods (after `retry()`):

```swift
    /// Permanently remove an item from Real-Debrid, purge its watch progress, and drop it from
    /// the in-memory library (optimistic). On failure the item is kept and `removal` becomes
    /// `.failed`. Safe to call from a confirmation handler.
    public func remove(_ item: MediaItem) async {
        removal = .removing(item)
        do {
            try await library.remove(item)
            try? await watch?.deleteProgress(forContentKeys: Self.contentKeys(for: item))
            movies.removeAll { $0.id == item.id }
            shows.removeAll { $0.id == item.id }
            if movies.isEmpty && shows.isEmpty { state = .empty }
            removal = .idle
        } catch {
            removal = .failed("Couldn't remove \u{201C}\(item.title)\u{201D}. Please try again.")
        }
    }

    /// Dismiss a surfaced removal error (call from the alert's OK button).
    public func clearRemovalError() { removal = .idle }

    /// Watch-progress keys an item owns: the movie key, or every episode key for a show.
    static func contentKeys(for item: MediaItem) -> [String] {
        switch item.kind {
        case .movie:
            return [WatchKey.content(forMovie: item)]
        case .show:
            return item.seasons.flatMap { season in
                season.episodes.map { WatchKey.content(forShow: item, episode: $0) }
            }
        }
    }
```

- [ ] **Step 7: Run the test, verify it passes**

Run: `cd Shared/DebridUI && swift test --filter LibraryStoreRemoveTests`
Expected: PASS (3 tests).

- [ ] **Step 8: Run the whole DebridUI suite (no regressions)**

Run: `cd Shared/DebridUI && swift test`
Expected: PASS, 0 failures.

- [ ] **Step 9: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Detail/WatchProgressProviding.swift \
        Shared/DebridUI/Sources/DebridUI/Library/LibraryStore.swift \
        Shared/DebridUI/Tests/DebridUITests/LibraryStoreRemoveTests.swift \
        Shared/DebridUI/Tests/DebridUITests/LibraryStoreTests.swift \
        Shared/DebridUI/Tests/DebridUITests/HomeStoreTests.swift \
        Shared/DebridUI/Tests/DebridUITests/DetailStoreTests.swift
git commit -m "feat(ui): LibraryStore.remove orchestrates RD delete + watch purge + optimistic drop"
```

---

## Task 4: AppSession — inject the watch store into LibraryStore

**Files:**
- Modify: `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift`

The current `enterSignedIn()` builds `LibraryStore(library: service)` (line ~124) *before* it builds `watchProgressStore`/`watchStore` (later in the method). Reorder so the watch store exists first, then inject it.

- [ ] **Step 1: Move the watch-store construction above the LibraryStore line**

In `enterSignedIn()`, cut these lines (currently below the `libraryStore = ...` line):

```swift
        let concreteStore = (try? ModelContainer(for: WatchProgress.self))
            .map { WatchProgressStore(modelContainer: $0) }
        watchProgressStore = concreteStore
        watchStore = concreteStore.map { $0 as WatchProgressProviding }
```

Paste them **immediately after** `let service = LibraryService(...)` is created and **before** the `libraryStore = LibraryStore(...)` line. Then change the `libraryStore` line to inject the watch seam:

```swift
        libraryStore = LibraryStore(library: service, watch: watchStore)
```

Leave the later `home = watchStore.map { HomeStore(watch: $0) }` line where it is (it still runs after, `watchStore` is already set).

- [ ] **Step 2: Build the DebridUI package**

Run: `cd Shared/DebridUI && swift build`
Expected: Build succeeds, 0 errors.

- [ ] **Step 3: Run the DebridUI suite**

Run: `cd Shared/DebridUI && swift test`
Expected: PASS, 0 failures (HomeStore still gets a non-nil watch store).

- [ ] **Step 4: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift
git commit -m "feat(ui): inject watch store into LibraryStore for progress purge on remove"
```

---

## Task 5: iOS — Remove from the detail screen

**Files:**
- Modify: `Apps/SeretMobile/Detail/DetailScreen.swift`

`DetailScreen` already has `@Environment(AppSession.self) private var session` and `@Environment(\.dismiss) private var dismiss`. Add an overflow menu, a confirmation dialog, and an error alert.

- [ ] **Step 1: Add removal state to `DetailScreen`**

Add these `@State` properties next to the existing ones:

```swift
    @State private var confirmingRemove = false
    @State private var removeError: String?
```

- [ ] **Step 2: Add the toolbar menu + confirm + alert**

In `body`, add a trailing toolbar item (alongside the existing leading chevron `ToolbarItem`), and attach the dialog/alert modifiers to the `NavigationStack`'s content. Add inside the `.toolbar { ... }` block:

```swift
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Remove from Library", systemImage: "trash", role: .destructive) {
                            confirmingRemove = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.headline)
                    }
                    .tint(Theme.Palette.gold)
                }
```

Then, after `.toolbarBackground(.hidden, for: .navigationBar)`, add:

```swift
            .confirmationDialog("Remove \u{201C}\(store.item.title)\u{201D} from your library?",
                                isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { performRemove() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes it from your Real‑Debrid account. You can re‑add it later by searching.")
            }
            .alert("Couldn't Remove", isPresented: Binding(
                get: { removeError != nil }, set: { if !$0 { removeError = nil } })) {
                Button("OK", role: .cancel) { removeError = nil }
            } message: {
                Text(removeError ?? "")
            }
```

- [ ] **Step 3: Add the `performRemove` helper**

Add to `DetailScreen` (next to `present`):

```swift
    private func performRemove() {
        guard let library = session.libraryStore else { return }
        Task {
            await library.remove(store.item)
            if case .failed(let message) = library.removal {
                removeError = message
                library.clearRemovalError()
            } else {
                dismiss()
            }
        }
    }
```

- [ ] **Step 4: Build the iOS app**

Run: `xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build`
(If that simulator name is unavailable, run `xcrun simctl list devices available | grep iPhone` and use one that exists.)
Expected: BUILD SUCCEEDED, 0 warnings.

- [ ] **Step 5: Commit**

```bash
git add Apps/SeretMobile/Detail/DetailScreen.swift
git commit -m "feat(ios): Remove from Library from the detail screen (confirm + dismiss)"
```

---

## Task 6: iOS — Remove from the poster grid

**Files:**
- Modify: `Apps/SeretMobile/Library/LibraryGrid.swift`
- Modify: `Apps/SeretMobile/Library/MyLibraryScreen.swift`

- [ ] **Step 1: Add an `onRemove` closure + context menu to `LibraryGrid`**

In `LibraryGrid`, add the property next to the other lets:

```swift
    let onRemove: (MediaItem) -> Void
```

In the `.loaded` branch, attach a context menu to the existing poster `Button`. Change:

```swift
                            Button { onSelect(item) } label: {
                                PosterCard(title: item.title,
                                           posterURL: TMDBClient.imageURL(path: item.posterPath, size: "w500"),
                                           width: nil)
                            }
                            .pressable()
```

to:

```swift
                            Button { onSelect(item) } label: {
                                PosterCard(title: item.title,
                                           posterURL: TMDBClient.imageURL(path: item.posterPath, size: "w500"),
                                           width: nil)
                            }
                            .pressable()
                            .contextMenu {
                                Button("Remove from Library", systemImage: "trash", role: .destructive) {
                                    onRemove(item)
                                }
                            }
```

- [ ] **Step 2: Wire confirmation + remove + error alert in `MyLibraryScreen`**

In `Apps/SeretMobile/Library/MyLibraryScreen.swift`, add state:

```swift
    @State private var pendingRemoval: MediaItem?
```

Pass `onRemove` to `LibraryGrid` (add the argument to the existing call):

```swift
                    LibraryGrid(
                        title: kind == .movie ? "Movies" : "Shows",
                        items: kind == .movie ? store.movies : store.shows,
                        state: store.state,
                        onRetry: { store.retry() },
                        onSelect: { router.detail = $0 },
                        onRemove: { pendingRemoval = $0 })
                        .task(id: store.attempt) { await store.load() }
                        .confirmationDialog(
                            "Remove \u{201C}\(pendingRemoval?.title ?? "")\u{201D} from your library?",
                            isPresented: Binding(get: { pendingRemoval != nil },
                                                 set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingRemoval) { item in
                            Button("Remove", role: .destructive) {
                                Task { await store.remove(item) }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: { _ in
                            Text("This deletes it from your Real‑Debrid account.")
                        }
                        .alert("Couldn't Remove", isPresented: Binding(
                            get: { if case .failed = store.removal { return true } else { return false } },
                            set: { if !$0 { store.clearRemovalError() } })) {
                            Button("OK", role: .cancel) { store.clearRemovalError() }
                        } message: {
                            if case .failed(let msg) = store.removal { Text(msg) }
                        }
```

- [ ] **Step 3: Build the iOS app**

Run: `xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED, 0 warnings.

- [ ] **Step 4: Commit**

```bash
git add Apps/SeretMobile/Library/LibraryGrid.swift Apps/SeretMobile/Library/MyLibraryScreen.swift
git commit -m "feat(ios): long-press a poster to Remove from Library (confirm + error alert)"
```

---

## Task 7: tvOS — Remove from the detail screen

**Files:**
- Modify: `Apps/SeretTV/Detail/DetailView.swift`
- Modify: `Apps/SeretTV/Detail/MovieDetailView.swift`
- Modify: `Apps/SeretTV/Detail/ShowDetailView.swift`

`DetailView` (tvOS) owns the confirm/dismiss and passes an `onRemove` closure into the two layouts, which render a focusable Remove button.

- [ ] **Step 1: Add `onRemove` param + Remove button to `MovieDetailView`**

In `Apps/SeretTV/Detail/MovieDetailView.swift`, add the property:

```swift
    let store: DetailStore
    var onRemove: () -> Void = {}
```

In the `actions` HStack, after `TrailerButton(...)`, add:

```swift
            Button(role: .destructive) { onRemove() } label: {
                Label("Remove from Library", systemImage: "trash")
            }
```

Update the `#Preview` `MovieDetailView(store:)` call — it stays valid because `onRemove` has a default.

- [ ] **Step 2: Add `onRemove` param + Remove button to `ShowDetailView`**

In `Apps/SeretTV/Detail/ShowDetailView.swift`, add the property:

```swift
    let store: DetailStore
    var onRemove: () -> Void = {}
```

Find the hero action row (the `hero` view's button group, near the Resume/Play-next buttons) and add a focusable Remove button at the end of that HStack:

```swift
            Button(role: .destructive) { onRemove() } label: {
                Label("Remove from Library", systemImage: "trash")
            }
```

(If the hero's actions are built in a helper like `heroActions`, add the button there. The button must be inside a focusable container so the tvOS focus engine can reach it.)

- [ ] **Step 3: Wire confirm + dismiss + error in `DetailView`**

Replace `Apps/SeretTV/Detail/DetailView.swift` body wiring so it owns the removal flow:

```swift
struct DetailView: View {
    @State private var store: DetailStore
    @State private var confirmingRemove = false
    @State private var removeError: String?
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    init(item: MediaItem, details: MediaDetailsProviding, watch: WatchProgressProviding?) {
        _store = State(initialValue: DetailStore(item: item, details: details, watch: watch))
    }

    var body: some View {
        Group {
            switch store.item.kind {
            case .movie: MovieDetailView(store: store, onRemove: { confirmingRemove = true })
            case .show:  ShowDetailView(store: store, onRemove: { confirmingRemove = true })
            }
        }
        .task { await store.load() }
        .alert("Remove \u{201C}\(store.item.title)\u{201D}?", isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive) { performRemove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes it from your Real‑Debrid account. You can re‑add it later by searching.")
        }
        .alert("Couldn't Remove", isPresented: Binding(
            get: { removeError != nil }, set: { if !$0 { removeError = nil } })) {
            Button("OK", role: .cancel) { removeError = nil }
        } message: {
            Text(removeError ?? "")
        }
    }

    private func performRemove() {
        guard let library = session.libraryStore else { return }
        Task {
            await library.remove(store.item)
            if case .failed(let message) = library.removal {
                removeError = message
                library.clearRemovalError()
            } else {
                dismiss()
            }
        }
    }
}
```

- [ ] **Step 4: Build the tvOS app**

Run: `xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' build`
(If unavailable, `xcrun simctl list devices available | grep "Apple TV"` and use an existing name.)
Expected: BUILD SUCCEEDED, 0 warnings.

- [ ] **Step 5: Commit**

```bash
git add Apps/SeretTV/Detail/DetailView.swift Apps/SeretTV/Detail/MovieDetailView.swift Apps/SeretTV/Detail/ShowDetailView.swift
git commit -m "feat(tvos): Remove from Library from the detail screen (confirm + dismiss)"
```

---

## Task 8: tvOS — Remove from the poster grid

**Files:**
- Modify: `Apps/SeretTV/Library/PosterCard.swift`
- Modify: `Apps/SeretTV/Library/PosterGrid.swift`
- Modify: `Apps/SeretTV/Library/LibraryScreen.swift`
- Modify: `Apps/SeretTV/Library/MyLibraryScreen.swift`

Thread an `onRemove` closure from `MyLibraryScreen` (owns the store) → `LibraryScreen` → `PosterGrid` → `PosterCard`, where a `.contextMenu` exposes Remove.

- [ ] **Step 1: `PosterCard` — add `onRemove` + context menu**

In `Apps/SeretTV/Library/PosterCard.swift`, add the property:

```swift
    let item: MediaItem
    var onRemove: (MediaItem) -> Void = { _ in }
```

Attach a context menu to the `NavigationLink`:

```swift
            NavigationLink(value: item) { poster }
                .buttonStyle(.card)
                .contextMenu {
                    Button("Remove from Library", systemImage: "trash", role: .destructive) {
                        onRemove(item)
                    }
                }
```

- [ ] **Step 2: `PosterGrid` — forward `onRemove`**

In `Apps/SeretTV/Library/PosterGrid.swift`:

```swift
    let items: [MediaItem]
    var onRemove: (MediaItem) -> Void = { _ in }
```

```swift
                ForEach(items) { PosterCard(item: $0, onRemove: onRemove) }
```

- [ ] **Step 3: `LibraryScreen` — forward `onRemove`**

In `Apps/SeretTV/Library/LibraryScreen.swift`, add the property to the struct:

```swift
    var onRemove: (MediaItem) -> Void = { _ in }
```

and pass it where `PosterGrid(items: items)` is built:

```swift
                PosterGrid(items: items, onRemove: onRemove)
```

- [ ] **Step 4: `MyLibraryScreen` (tvOS) — confirm + remove + error alert**

In `Apps/SeretTV/Library/MyLibraryScreen.swift`, add state:

```swift
    @State private var pendingRemoval: MediaItem?
```

Update the `LibraryScreen(...)` call to pass `onRemove` and attach the dialogs (note: `store` is captured from the `if let store = session.libraryStore` binding):

```swift
                LibraryScreen(
                    title: kind == .movie ? "Movies" : "Shows",
                    items: kind == .movie ? store.movies : store.shows,
                    state: store.state,
                    onRetry: { store.retry() },
                    onRemove: { pendingRemoval = $0 })
                    .alert("Remove \u{201C}\(pendingRemoval?.title ?? "")\u{201D}?",
                           isPresented: Binding(get: { pendingRemoval != nil },
                                                set: { if !$0 { pendingRemoval = nil } })) {
                        Button("Remove", role: .destructive) {
                            if let item = pendingRemoval { Task { await store.remove(item) } }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This deletes it from your Real‑Debrid account.")
                    }
                    .alert("Couldn't Remove", isPresented: Binding(
                        get: { if case .failed = store.removal { return true } else { return false } },
                        set: { if !$0 { store.clearRemovalError() } })) {
                        Button("OK", role: .cancel) { store.clearRemovalError() }
                    } message: {
                        if case .failed(let msg) = store.removal { Text(msg) }
                    }
```

- [ ] **Step 5: Build the tvOS app**

Run: `xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' build`
Expected: BUILD SUCCEEDED, 0 warnings.

- [ ] **Step 6: Commit**

```bash
git add Apps/SeretTV/Library/PosterCard.swift Apps/SeretTV/Library/PosterGrid.swift \
        Apps/SeretTV/Library/LibraryScreen.swift Apps/SeretTV/Library/MyLibraryScreen.swift
git commit -m "feat(tvos): long-press a poster to Remove from Library (confirm + error alert)"
```

---

## Task 9: Full verification

- [ ] **Step 1: Run both package suites**

Run: `cd Packages/DebridCore && swift test && cd ../../Shared/DebridUI && swift test`
Expected: All pass, 0 failures.

- [ ] **Step 2: Build both apps clean**

Run:
```bash
xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' build
xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: BUILD SUCCEEDED, 0 warnings for both.

- [ ] **Step 3: Owner-pending on-device check (do not fake)**

Real RD deletion cannot be safely verified from the sim without a throwaway item, and the library only populates with a signed-in RD token. Note in the final summary that the following is **owner-pending**, exactly like the player DoD:
  - Sign in with the RD token, long-press a poster → Remove → confirm → tile disappears and the item is gone from the RD account.
  - Repeat from the detail screen → screen pops back to the grid.
  - A removed in-progress title no longer appears under Home → Continue Watching.

---

## Self-Review Notes

- **Spec coverage:** RD-delete of all torrents (Task 1) · 404 idempotency (Task 1) · partial-failure preserves snapshot (Task 1) · watch purge (Tasks 2–3) · optimistic drop (Task 3) · both apps, grid + detail, confirm-gated (Tasks 5–8) · injection wiring (Task 4) · tests + build verification (Task 9). All spec sections map to a task.
- **Type consistency:** `LibraryStore.Removal` (`.idle`/`.removing`/`.failed`), `remove(_:)`, `clearRemovalError()`, `contentKeys(for:)`, `LibraryService.remove(_:)`/`torrentIDs(for:)`, `WatchProgressStore.deleteProgress(forContentKeys:)`, seam additions to `LibraryProviding`/`WatchProgressProviding` — names used identically across producer and consumer tasks.
- **Conformers updated:** every existing `LibraryProviding`/`WatchProgressProviding` conformer (LibraryService, WatchProgressStore, and the three test fakes) gains the new methods in Tasks 1–3, so no build breaks.
- **Scope:** single feature, one plan. No undo/bulk/hidden-layer (explicitly out of scope).
