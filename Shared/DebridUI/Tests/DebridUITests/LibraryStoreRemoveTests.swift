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
    func removeVersion(_ item: MediaItem, source: MediaSource) async throws {
        if let e = removeError { throw e }
    }
}

private actor RecordingWatch: WatchProgressProviding {
    private(set) var deletedKeys: [String] = []
    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { nil }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws {}
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
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
        #expect(await watch.deletedKeys == ["1"])
    }

    @Test func removingAShowPurgesEpisodeKeys() async {
        let watch = RecordingWatch()
        let store = LibraryStore(library: RemoveFakeLibrary(cached: [showWithEpisodes("2")]), watch: watch)
        await store.load()
        await store.remove(store.shows[0])
        #expect(store.shows.isEmpty)
        #expect(await watch.deletedKeys == ["2:s1e1"])
    }

    @Test func failureSetsErrorAndKeepsItem() async {
        let watch = RecordingWatch()
        let store = LibraryStore(
            library: RemoveFakeLibrary(cached: [movie("1")], removeError: .boom), watch: watch)
        await store.load()
        await store.remove(store.movies[0])
        #expect(store.movies.count == 1)
        #expect(await watch.deletedKeys.isEmpty)   // watch purge must NOT run when RD delete fails
        guard case .failed = store.removal else {
            #expect(Bool(false), "expected .failed, got \(store.removal)"); return
        }
        store.clearRemovalError()
        #expect(store.removal == .idle)
    }

    @Test func successNotifiesContentChanged() async {
        let store = LibraryStore(library: RemoveFakeLibrary(cached: [movie("1")]), watch: RecordingWatch())
        var notifications = 0
        store.onContentChanged = { notifications += 1 }
        await store.load()
        await store.remove(store.movies[0])
        #expect(notifications == 1)   // dependent rails (Home) get a chance to recompute
    }

    @Test func failureDoesNotNotifyContentChanged() async {
        let store = LibraryStore(
            library: RemoveFakeLibrary(cached: [movie("1")], removeError: .boom), watch: RecordingWatch())
        var notifications = 0
        store.onContentChanged = { notifications += 1 }
        await store.load()
        await store.remove(store.movies[0])
        #expect(notifications == 0)   // nothing changed, so no rebuild
    }
}
