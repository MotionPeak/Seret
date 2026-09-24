import Testing
import Foundation
import DebridCore
@testable import DebridUI

@MainActor
@Suite struct HomeStoreHebrewTests {
    private struct Watch: WatchProgressProviding {
        var states: [WatchState]
        func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { states }
        func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { nil }
        func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                    durationSeconds: Double, finished: Bool, profileID: String) async throws {}
        func deleteProgress(forContentKeys keys: [String]) async throws {}
    }

    private let uhd = MediaSource(torrentID: "A", fileID: 1, restrictedLink: "a",
                                  parsed: ParsedRelease(title: "T", resolution: "2160p"))
    private let hd = MediaSource(torrentID: "B", fileID: 1, restrictedLink: "b",
                                 parsed: ParsedRelease(title: "T", resolution: "1080p"))

    private func home(evidence: FakeSubtitleEvidence?) async -> HomeStore {
        let movie = MediaItem(id: "movie:tmdb:1", kind: .movie, title: "T", year: 2023,
                              sources: [uhd, hd], seasons: [], tmdbID: 1)
        let state = WatchState(contentKey: "movie:tmdb:1", sourceKey: WatchKey.source(uhd),
                               positionSeconds: 60, durationSeconds: 6000, finished: false, updatedAt: Date())
        let store = HomeStore(watch: Watch(states: [state]), subtitleEvidence: evidence)
        store.activeProfileID = "p"
        await store.rebuild(movies: [movie], shows: [])
        return store
    }

    @Test func resumePlaysTheCopyTheTitlePageWould() async {
        let stored = SubtitleEvidenceSet(byVersion: [WatchKey.source(hd): SubtitleEvidence(hebrew: .builtIn)],
                                         originalLanguage: "en")
        let store = await home(evidence: FakeSubtitleEvidence(stored: stored))
        #expect(store.continueWatching.first?.source == hd)
    }

    @Test func withoutEvidenceResumeIsUnchanged() async {
        let store = await home(evidence: nil)
        #expect(store.continueWatching.first?.source == uhd)
    }
}
