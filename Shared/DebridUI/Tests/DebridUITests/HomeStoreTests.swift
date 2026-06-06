import Testing
import Foundation
@testable import DebridUI
import DebridCore

private struct FakeWatch: WatchProgressProviding {
    var states: [WatchState]
    func recentlyWatched(limit: Int) async throws -> [WatchState] { Array(states.prefix(limit)) }
    func progress(forContentKey key: String) async throws -> WatchState? { nil }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool) async throws {}
}

@Suite struct HomeStoreTests {
    @MainActor @Test func resolvesMovieAndShowProgress() async {
        let movie = MediaItem(id: "movie:dune:2021", kind: .movie, title: "Dune", year: 2021, sources: [], seasons: [])
        let show  = MediaItem(id: "show:bb", kind: .show, title: "Breaking Bad", year: 2008, sources: [], seasons: [])
        let states = [
            WatchState(contentKey: "movie:dune:2021", sourceKey: "t#f", positionSeconds: 30, durationSeconds: 120, finished: false, updatedAt: Date()),
            WatchState(contentKey: "show:bb:s3e4", sourceKey: "t#f", positionSeconds: 600, durationSeconds: 1200, finished: false, updatedAt: Date()),
        ]
        let store = HomeStore(watch: FakeWatch(states: states))
        await store.rebuild(movies: [movie], shows: [show])
        #expect(store.continueWatching.count == 2)
        #expect(store.continueWatching[0].item.id == "movie:dune:2021")
        #expect(abs(store.continueWatching[0].fraction - 0.25) < 0.001)
        #expect(store.continueWatching[1].item.id == "show:bb")
        #expect(store.continueWatching[1].subtitle == "S3 · E4")
    }

    @MainActor @Test func recentlyAddedSortsDescAndSkipsNil() async {
        let older = MediaItem(id: "a", kind: .movie, title: "A", year: nil, sources: [], seasons: [], addedAt: Date(timeIntervalSince1970: 1000))
        let newer = MediaItem(id: "b", kind: .movie, title: "B", year: nil, sources: [], seasons: [], addedAt: Date(timeIntervalSince1970: 2000))
        let undated = MediaItem(id: "c", kind: .movie, title: "C", year: nil, sources: [], seasons: [])
        let store = HomeStore(watch: FakeWatch(states: []))
        await store.rebuild(movies: [older, newer, undated], shows: [])
        #expect(store.recentlyAdded.map(\.id) == ["b", "a"])
    }
}
