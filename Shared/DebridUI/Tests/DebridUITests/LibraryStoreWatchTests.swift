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

    @Test func watchStateIsMoviesOnly() async {
        // A show poster isn't one watchable unit — watchState(for:) is nil for shows even if the
        // show id happens to match a stored key.
        let watch = FakeWatch(["": ["2": watched("2")]])
        let store = LibraryStore(library: WatchFakeLibrary(items: [show("2")]), watch: watch)
        await store.load()
        #expect(store.watchState(for: show("2")) == nil)
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
