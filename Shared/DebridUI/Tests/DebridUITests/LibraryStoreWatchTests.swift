import Testing
import Foundation
import DebridCore
@testable import DebridUI

private func movie(_ id: String) -> MediaItem {
    MediaItem(id: id, kind: .movie, title: "Movie \(id)", year: 2024, sources: [], seasons: [])
}
private func movieWithSource(_ id: String) -> MediaItem {
    MediaItem(id: id, kind: .movie, title: "Movie \(id)", year: 2024,
              sources: [MediaSource(torrentID: "t\(id)", fileID: nil, restrictedLink: "l",
                                    parsed: ParsedRelease(title: "x"))], seasons: [])
}
private func show(_ id: String) -> MediaItem {
    MediaItem(id: id, kind: .show, title: "Show \(id)", year: 2023, sources: [], seasons: [])
}
private func watched(_ key: String) -> WatchState {
    WatchState(contentKey: key, sourceKey: "s", positionSeconds: 0, durationSeconds: 0,
               finished: true, updatedAt: Date(timeIntervalSince1970: 1))
}

/// A mutable profile holder so a test can flip the active profile the store reads through.
private final class ProfileBox { var id: String? }

private struct WatchFakeLibrary: LibraryProviding {
    let items: [MediaItem]
    func loadCached() -> [MediaItem]? { items }
    func refresh() async throws -> [MediaItem] { items }
    func remove(_ item: MediaItem) async throws {}
    func removeVersion(_ item: MediaItem, source: MediaSource) async throws {}
}

/// Per-profile watch double. Only implements the per-key requirements; the batched read falls back
/// to the protocol default (a loop over `progress(forContentKey:)`) — exactly what the store uses.
private actor FakeWatch: WatchProgressProviding {
    private var byProfile: [String: [String: WatchState]]
    private(set) var recorded: [(key: String, finished: Bool, profile: String)] = []
    init(_ seed: [String: [String: WatchState]] = [:]) { byProfile = seed }
    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? {
        byProfile[profileID]?[key]
    }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws {
        recorded.append((contentKey, finished, profileID))
        byProfile[profileID, default: [:]][contentKey] = WatchState(
            contentKey: contentKey, sourceKey: sourceKey, positionSeconds: positionSeconds,
            durationSeconds: durationSeconds, finished: finished, updatedAt: Date(timeIntervalSince1970: 1))
    }
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
    func deleteProgress(forContentKeys keys: [String]) async throws {}
}

@MainActor
@Suite struct LibraryStoreWatchTests {
    @Test func loadPopulatesMovieWatchStates() async {
        let watch = FakeWatch(["": ["1": watched("1")]])
        let store = LibraryStore(library: WatchFakeLibrary(items: [movie("1"), movie("3"), show("2")]),
                                 watch: watch)
        await store.load()
        #expect(store.watchState(for: movie("1"))?.finished == true)
        #expect(store.watchState(for: movie("3")) == nil)   // no state seeded for this movie
    }

    /// Superseded on purpose. This used to assert `watchState(for:)` was nil for a show, on the
    /// reasoning that a series is not one watchable unit. But `ShowWatchMarker` writes a series key
    /// anyway, Browse reads it, and Detail can mark a whole show — so the only thing the old rule
    /// achieved was that a show ticked in one grid and not in the other.
    @Test func watchStateAnswersForShowsToo() async {
        let watch = FakeWatch(["": ["2": watched("2")]])
        let store = LibraryStore(library: WatchFakeLibrary(items: [show("2")]), watch: watch)
        await store.load()
        #expect(store.watchState(for: show("2"))?.finished == true)
    }

    @Test func setWatchedMarksMovieAndUpdatesMap() async {
        let watch = FakeWatch()
        let store = LibraryStore(library: WatchFakeLibrary(items: [movieWithSource("1")]), watch: watch)
        await store.load()
        #expect(store.watchState(for: movieWithSource("1")) == nil)
        await store.setWatched(true, for: movieWithSource("1"))
        #expect(store.watchState(for: movieWithSource("1"))?.finished == true)
        #expect(await watch.recorded.map(\.finished) == [true])
    }

    @Test func setWatchedUnmarksMovie() async {
        let watch = FakeWatch(["": ["1": watched("1")]])
        let store = LibraryStore(library: WatchFakeLibrary(items: [movieWithSource("1")]), watch: watch)
        await store.load()
        #expect(store.watchState(for: movieWithSource("1"))?.finished == true)
        await store.setWatched(false, for: movieWithSource("1"))
        #expect(store.watchState(for: movieWithSource("1"))?.finished == false)
    }

    @Test func setWatchedIgnoresShows() async {
        let watch = FakeWatch()
        let store = LibraryStore(library: WatchFakeLibrary(items: [show("2")]), watch: watch)
        await store.load()
        await store.setWatched(true, for: show("2"))
        #expect(await watch.recorded.isEmpty)   // shows can't be marked from the grid
    }

    @Test func setWatchedFiresContentChanged() async {
        let store = LibraryStore(library: WatchFakeLibrary(items: [movieWithSource("1")]), watch: FakeWatch())
        var changed = 0
        store.onContentChanged = { changed += 1 }
        await store.load()
        await store.setWatched(true, for: movieWithSource("1"))
        #expect(changed == 1)   // Home rails get a chance to drop the now-finished movie
    }

    @Test func reloadWatchStatesReflectsProfileSwitch() async {
        let box = ProfileBox(); box.id = "A"
        let watch = FakeWatch(["A": ["1": watched("1")], "B": [:]])
        let store = LibraryStore(library: WatchFakeLibrary(items: [movie("1")]),
                                 watch: watch, profileID: { box.id })
        await store.load()
        #expect(store.watchState(for: movie("1"))?.finished == true)
        box.id = "B"
        await store.reloadWatchStates()
        #expect(store.watchState(for: movie("1")) == nil)   // profile B hasn't watched it
    }

    @Test func noWatchSeamLeavesStatesEmpty() async {
        let store = LibraryStore(library: WatchFakeLibrary(items: [movie("1")]))
        await store.load()
        #expect(store.watchState(for: movie("1")) == nil)   // degrades cleanly with no seam
    }
}

/// A show marked watched shows a tick in Browse but not in My Library, and its poster offered no
/// way to mark it at all — the same title behaved differently depending on which grid you found it
/// in. `ShowWatchMarker` already writes the series key (the show's own id, exactly like a movie's),
/// so the state existed; the library grid simply never read it.
@MainActor
@Suite struct LibraryStoreShowWatchTests {
    @Test func aWatchedShowReportsItsStateToTheLibraryGrid() async {
        let watch = FakeWatch(["": ["2": watched("2")]])
        let store = LibraryStore(library: WatchFakeLibrary(items: [movie("1"), show("2")]),
                                 watch: watch)
        await store.load()
        #expect(store.watchState(for: show("2"))?.finished == true)
    }

    @Test func anUnwatchedShowReportsNothing() async {
        let watch = FakeWatch(["": [:]])
        let store = LibraryStore(library: WatchFakeLibrary(items: [show("2")]), watch: watch)
        await store.load()
        #expect(store.watchState(for: show("2")) == nil)
    }
}


/// Counts how many times a refresh actually reached the library layer.
private actor RefreshCounter {
    private(set) var count = 0
    func bump() { count += 1 }
}

private struct CountingLibrary: LibraryProviding {
    let items: [MediaItem]
    let counter: RefreshCounter
    let gate: @Sendable () async -> Void
    func loadCached() -> [MediaItem]? { nil }
    func refresh() async throws -> [MediaItem] {
        await counter.bump()
        await gate()
        return items
    }
    func remove(_ item: MediaItem) async throws {}
    func removeVersion(_ item: MediaItem, source: MediaSource) async throws {}
}

@MainActor
@Suite struct LibraryStoreLoadCoalescingTests {
    /// Two screens share one store — on iPhone, Home and My Library both ask it to load — and each
    /// used to run its own refresh: the whole Real-Debrid pagination, the /torrents/info fan-out
    /// and a TMDB enrichment pass, twice over, for one answer.
    @Test func twoConcurrentLoadsRefreshTheLibraryOnce() async {
        let counter = RefreshCounter()
        let released = Gate()
        let library = CountingLibrary(items: [movie("1")], counter: counter,
                                      gate: { await released.wait() })
        let store = LibraryStore(library: library)

        async let first: Void = store.load()
        async let second: Void = store.load()
        await Task.yield()
        await released.open()
        _ = await (first, second)

        #expect(await counter.count == 1)
        #expect(store.movies.count == 1)
    }

    /// …and a LATER load still works: coalescing must not latch.
    @Test func aLoadAfterTheFirstCompletesStillRefreshes() async {
        let counter = RefreshCounter()
        let released = Gate()
        await released.open()
        let library = CountingLibrary(items: [movie("1")], counter: counter,
                                      gate: { await released.wait() })
        let store = LibraryStore(library: library)
        await store.load()
        await store.load()
        #expect(await counter.count == 2)
    }


    /// A reload asked for WHILE a load is running must still run.
    ///
    /// The joiner and the owner both resume when the in-flight task finishes. When the joiner
    /// cleared the pending flag it re-entered, joined the same already-finished task and returned,
    /// leaving the owner with nothing to do — so the reload was silently dropped, in exactly the
    /// case it exists for: a download landing mid-refresh still never reached the library.
    @Test func aReloadDuringAnInFlightLoadStillRuns() async {
        let counter = RefreshCounter()
        let released = Gate()
        let library = CountingLibrary(items: [movie("1")], counter: counter,
                                      gate: { await released.wait() })
        let store = LibraryStore(library: library)

        async let owner: Void = store.load()          // the in-flight refresh
        // Wait until it is genuinely in flight (blocked on the gate), not merely scheduled.
        while await counter.count < 1 { await Task.yield() }

        store.reload()                                 // …a download lands mid-flight
        async let joiner: Void = store.load()          // …and a screen asks too
        await Task.yield()
        await released.open()
        _ = await (owner, joiner)
        // Let the follow-up run to completion.
        for _ in 0..<50 { await Task.yield() }

        #expect(await counter.count == 2)              // the reload actually happened
    }


    /// `retry()` is what the instant-add screens call when a torrent lands in RD, and the shell's
    /// `.task(id: attempt)` re-fires into `load()`. Coalescing made that re-entry JOIN the refresh
    /// already running — which was fetched before the torrent existed — so the newly added title
    /// was absent from the library, and the shell being the mounted root, its task would not fire
    /// again on its own. `reload()` was given a pending-follow-up flag for exactly this; `retry()`
    /// was left a bare counter bump, and it is the call four of the six add sites use.
    @Test func aRetryDuringAnInFlightLoadStillRefreshes() async {
        let counter = RefreshCounter()
        let released = Gate()
        let library = CountingLibrary(items: [movie("1")], counter: counter,
                                      gate: { await released.wait() })
        let store = LibraryStore(library: library)

        async let owner: Void = store.load()
        while await counter.count < 1 { await Task.yield() }

        store.retry()                                  // …a torrent was just added
        async let refire: Void = store.load()          // the shell's .task(id: attempt) re-firing
        await Task.yield()
        await released.open()
        _ = await (owner, refire)
        for _ in 0..<50 { await Task.yield() }

        #expect(await counter.count == 2)
    }

    private actor Gate {
        private var opened = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func open() { opened = true; for w in waiters { w.resume() }; waiters = [] }
        func wait() async {
            if opened { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }
}
