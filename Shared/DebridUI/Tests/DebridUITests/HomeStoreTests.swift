import Testing
import Foundation
@testable import DebridUI
import DebridCore

private struct FakeWatch: WatchProgressProviding {
    var states: [WatchState]
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] {
        Array(states.prefix(limit))
    }
    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { nil }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws {}
    func deleteProgress(forContentKeys keys: [String]) async throws {}
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
        store.activeProfileID = "p1"
        await store.rebuild(movies: [movie], shows: [show])
        #expect(store.continueWatching.count == 2)
        #expect(store.continueWatching[0].item.id == "movie:dune:2021")
        #expect(abs(store.continueWatching[0].fraction - 0.25) < 0.001)
        #expect(store.continueWatching[1].item.id == "show:bb")
        #expect(store.continueWatching[1].subtitle == "S3 · E4")
    }

    @MainActor @Test func resumeFromHomeResolvesTheExactEpisodeSourceAndPosition() async {
        let src = MediaSource(torrentID: "t9", fileID: 3, restrictedLink: "rd://ep",
                              parsed: ParsedRelease(title: "Invincible", season: 4, episode: 1, resolution: "2160p"))
        let episode = Episode(season: 4, number: 1, source: src)
        let show = MediaItem(id: "show:inv", kind: .show, title: "Invincible", year: 2021,
                             sources: [], seasons: [Season(number: 4, episodes: [episode])])
        let states = [WatchState(contentKey: "show:inv:s4e1", sourceKey: "t9#3",
                                 positionSeconds: 353, durationSeconds: 3000, finished: false, updatedAt: Date())]
        let store = HomeStore(watch: FakeWatch(states: states))
        store.activeProfileID = "p1"
        await store.rebuild(movies: [], shows: [show])

        let hi = store.continueWatching[0]
        #expect(hi.isResumable)
        let req = hi.playbackRequest()
        #expect(req?.source == src)                       // the exact episode file, not the show's first
        #expect(req?.episode == episode)
        #expect(req?.contentKey == "show:inv:s4e1")        // progress keys back to the same episode
        #expect(req?.resumeAt == 353)                      // resumes where it left off
        #expect(req?.fromStart == false)
        #expect(req?.label == "Invincible — S4·E1")
    }

    @MainActor @Test func finishedOrUnresolvedEntriesAreNotDirectlyResumable() async {
        // A show whose watched episode is no longer in the library (version removed) → no source.
        let show = MediaItem(id: "show:x", kind: .show, title: "X", year: nil, sources: [], seasons: [])
        let states = [WatchState(contentKey: "show:x:s1e1", sourceKey: "t#f",
                                 positionSeconds: 10, durationSeconds: 100, finished: false, updatedAt: Date())]
        let store = HomeStore(watch: FakeWatch(states: states))
        store.activeProfileID = "p1"
        await store.rebuild(movies: [], shows: [show])
        let hi = store.continueWatching[0]
        #expect(!hi.isResumable)                           // unresolved → UI falls back to Detail
        #expect(hi.playbackRequest() == nil)
    }

    @MainActor @Test func recentlyAddedSortsDescAndSkipsNil() async {
        let older = MediaItem(id: "a", kind: .movie, title: "A", year: nil, sources: [], seasons: [], addedAt: Date(timeIntervalSince1970: 1000))
        let newer = MediaItem(id: "b", kind: .movie, title: "B", year: nil, sources: [], seasons: [], addedAt: Date(timeIntervalSince1970: 2000))
        let undated = MediaItem(id: "c", kind: .movie, title: "C", year: nil, sources: [], seasons: [])
        let store = HomeStore(watch: FakeWatch(states: []))
        store.activeProfileID = "p1"
        await store.rebuild(movies: [older, newer, undated], shows: [])
        #expect(store.recentlyAdded.map(\.id) == ["b", "a"])
    }
}
