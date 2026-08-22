import Testing
import Foundation
import DebridCore
@testable import DebridUI

private func movie(_ id: String) -> MediaItem {
    MediaItem(id: id, kind: .movie, title: "Movie \(id)", year: 2024, sources: [], seasons: [])
}

/// Opening the library grid starts a refresh, and that refresh spends a second or two inside RD's
/// paginated torrent list before it returns. Removing a title inside that window is the normal
/// case, not an unlucky one — the long-press that starts a removal is a thing you do right after
/// the screen appears.
private final class SlowRefreshLibrary: LibraryProviding, @unchecked Sendable {
    let items: [MediaItem]
    private let gate: Gate
    init(items: [MediaItem], gate: Gate) { self.items = items; self.gate = gate }
    func loadCached() -> [MediaItem]? { items }
    /// Returns the list as it looked BEFORE the removal — which is what an RD call already in
    /// flight comes back with.
    func refresh() async throws -> [MediaItem] {
        await gate.wait()
        return items
    }
    func remove(_ item: MediaItem) async throws {}
    func removeVersion(_ item: MediaItem, source: MediaSource) async throws {}
}

private actor Gate {
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
@Suite struct LibraryStoreRemoveRaceTests {

    /// Wait for the cache-first render, which `load()` reaches only after an off-main hop.
    private func awaitCachedRender(_ store: LibraryStore) async {
        for _ in 0..<200 where store.movies.isEmpty {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// **"Removing from the library most times doesn't work."**
    ///
    /// The removal itself succeeded — the torrent really was deleted at Real-Debrid — but a refresh
    /// that had started BEFORE it finished afterwards and applied the list it had already fetched,
    /// putting the deleted title straight back on the grid. Nothing cancelled or invalidated that
    /// in-flight load, so the tile reappeared seconds after it vanished and the removal read as a
    /// no-op.
    @Test func aRefreshAlreadyInFlightCannotPutARemovedTitleBack() async {
        let gate = Gate()
        let store = LibraryStore(library: SlowRefreshLibrary(items: [movie("1"), movie("2")],
                                                            gate: gate))
        let load = Task { await store.load() }
        await awaitCachedRender(store)
        #expect(store.movies.count == 2)          // the cache rendered; the refresh is still out

        await store.remove(store.movies[0])       // …and the viewer removes one meanwhile
        #expect(store.movies.map(\.id) == ["2"])

        await gate.open()                         // the stale refresh lands
        await load.value

        #expect(store.movies.map(\.id) == ["2"])
    }

    /// Same window, one version deleted rather than the whole title.
    @Test func aRefreshAlreadyInFlightCannotPutARemovedVersionBack() async {
        let source = MediaSource(torrentID: "t1", fileID: nil, restrictedLink: "l",
                                 parsed: ParsedRelease(title: "x"))
        let withVersion = MediaItem(id: "1", kind: .movie, title: "Movie 1", year: 2024,
                                    sources: [source], seasons: [])
        let gate = Gate()
        let store = LibraryStore(library: SlowRefreshLibrary(items: [withVersion], gate: gate))
        let load = Task { await store.load() }
        await awaitCachedRender(store)

        await store.removeVersion(store.movies[0], source: source)
        #expect(store.movies.isEmpty)             // it was the only version → the title goes too

        await gate.open()
        await load.value

        #expect(store.movies.isEmpty)
    }

    /// The guard must not swallow a refresh that simply finishes normally.
    @Test func anUndisturbedRefreshStillApplies() async {
        let gate = Gate()
        let store = LibraryStore(library: SlowRefreshLibrary(items: [movie("1"), movie("2")],
                                                            gate: gate))
        await gate.open()
        await store.load()
        #expect(store.movies.map(\.id) == ["1", "2"])
        #expect(store.state == .loaded)
    }
}
