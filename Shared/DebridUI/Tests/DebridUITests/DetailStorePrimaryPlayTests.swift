import Testing
import Foundation
import DebridCore
@testable import DebridUI

/// `primaryPlay()` / `episodePlayRequest(for:)` are the one shared answer to "what do Play, Resume
/// and Start Over send to the player" — lifted out of the iPhone/tvOS Detail views (Decision 1,
/// 2026-09-23 Mac watch-slice plan) so the Mac does not become a third copy of that logic.
@MainActor
@Suite struct DetailStorePrimaryPlayTests {

    private enum Boom: Error { case noDetails }

    private struct NoDetails: MediaDetailsProviding {
        func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw Boom.noDetails }
        func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw Boom.noDetails }
        func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
    }

    private actor WatchSpy: WatchProgressProviding {
        private let states: [String: WatchState]
        init(_ states: [String: WatchState]) { self.states = states }

        func progress(forContentKey key: String, profileID: String) async throws -> WatchState? {
            states[key]
        }
        func progress(forContentKeys keys: [String], profileID: String) async throws -> [String: WatchState] {
            states.filter { keys.contains($0.key) }
        }
        func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                    durationSeconds: Double, finished: Bool, profileID: String) async throws {}
        func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
        func deleteProgress(forContentKeys keys: [String]) async throws {}
    }

    /// Names one source key as preferred, no matter which content key is asked.
    private actor FixedPreference: VersionPreferring {
        private let key: String
        init(_ key: String) { self.key = key }
        func preferred(forContentKey key: String) async -> String? { self.key }
        func choose(contentKey: String, sourceKey: String) async {}
        func clear(contentKey: String) async {}
    }

    private func src(_ id: String, _ res: String) -> MediaSource {
        MediaSource(torrentID: id, fileID: nil, restrictedLink: "rd://\(id)",
                    parsed: ParsedRelease(title: "t", resolution: res))
    }

    private func film(_ sources: [MediaSource]) -> MediaItem {
        MediaItem(id: "movie:tmdb:1", kind: .movie, title: "Film", year: 2024,
                 sources: sources, seasons: [], tmdbID: nil)
    }

    private func show() -> MediaItem {
        let s1 = Season(number: 1, episodes: [
            Episode(season: 1, number: 1, source: src("s1e1", "1080p")),
        ])
        let s2 = Season(number: 2, episodes: [
            Episode(season: 2, number: 1, source: src("s2e1", "1080p")),
            Episode(season: 2, number: 2, source: src("s2e2", "1080p")),
            Episode(season: 2, number: 3, source: src("s2e3", "1080p")),
        ])
        return MediaItem(id: "show:tmdb:200", kind: .show, title: "Show", year: 2020,
                         sources: [], seasons: [s1, s2], tmdbID: nil)
    }

    private func finished(_ key: String, position: Double = 100, duration: Double = 100) -> WatchState {
        WatchState(contentKey: key, sourceKey: "s", positionSeconds: position, durationSeconds: duration,
                   finished: true, updatedAt: Date(timeIntervalSince1970: 1))
    }
    private func inProgress(_ key: String, position: Double, duration: Double) -> WatchState {
        WatchState(contentKey: key, sourceKey: "s", positionSeconds: position, durationSeconds: duration,
                   finished: false, updatedAt: Date(timeIntervalSince1970: 2))
    }

    @Test func aFilmNeverStartedPlaysItsBestSourceFromTheStart() async {
        let item = film([src("t", "1080p")])
        let store = DetailStore(item: item, details: NoDetails(), watch: WatchSpy([:]))
        await store.load()

        let pp = store.primaryPlay()
        #expect(pp?.resumeAt == nil)
        #expect(pp?.request.source == store.bestSource)
        #expect(pp?.request.label == item.title)
        #expect(pp?.request.contentKey == item.id)
    }

    @Test func aFilmHalfWatchedResumesAndOffersStartOver() async {
        let item = film([src("t", "1080p")])
        let key = WatchKey.content(forMovie: item)
        let store = DetailStore(item: item, details: NoDetails(),
                                watch: WatchSpy([key: inProgress(key, position: 3753, duration: 8160)]))
        await store.load()

        let pp = store.primaryPlay()
        #expect(pp?.resumeAt == 3753)
        #expect(pp?.request.resumeAt == 3753)
        #expect(pp?.startOver.fromStart == true)
        #expect(pp?.startOver.resumeAt == nil)
    }

    @Test func aFilmWatchedToTheEndHasNoResume() async {
        let item = film([src("t", "1080p")])
        let key = WatchKey.content(forMovie: item)
        let store = DetailStore(item: item, details: NoDetails(),
                                watch: WatchSpy([key: finished(key, position: 8150, duration: 8160)]))
        await store.load()

        #expect(store.primaryPlay()?.resumeAt == nil)
    }

    @Test func thePreferredVersionIsWhatPlays() async {
        let low = src("a", "720p")
        let high = src("b", "2160p")
        let item = film([low, high])
        #expect(item.sources.bestFirst().first?.torrentID == "b")   // sanity: the ranker prefers "b"

        let store = DetailStore(item: item, details: NoDetails(), watch: WatchSpy([:]),
                                versionPrefs: FixedPreference(WatchKey.source(low)))
        await store.load()
        await store.loadPreferredVersion()

        #expect(store.primaryPlay()?.request.source == low)
    }

    @Test func aShowPlaysTheEpisodeInProgressWithTheSharedLabel() async {
        let item = show()
        let episode = item.seasons[1].episodes[2]   // S2E3
        let key = WatchKey.content(forShow: item, episode: episode)
        let store = DetailStore(item: item, details: NoDetails(),
                                watch: WatchSpy([key: inProgress(key, position: 300, duration: 3000)]))
        await store.load()
        await store.reloadWatch()

        let pp = store.primaryPlay()
        #expect(pp?.episode?.season == 2)
        #expect(pp?.episode?.number == 3)
        #expect(pp?.request.label == "Show — S2·E3")
        #expect(pp?.request.contentKey == key)
    }

    @Test func specialsNeverWinForAShowNotStarted() async {
        let specials = Season(number: 0, episodes: [Episode(season: 0, number: 1, source: src("s0e1", "1080p"))])
        let s1 = Season(number: 1, episodes: [Episode(season: 1, number: 1, source: src("s1e1", "1080p"))])
        let item = MediaItem(id: "show:tmdb:201", kind: .show, title: "Show", year: 2020,
                             sources: [], seasons: [specials, s1], tmdbID: nil)
        let store = DetailStore(item: item, details: NoDetails(), watch: WatchSpy([:]))
        await store.load()

        let pp = store.primaryPlay()
        #expect(pp?.episode?.season == 1)
        #expect(pp?.episode?.number == 1)
    }

    @Test func nothingOwnedMeansNoPrimaryPlay() async {
        let item = film([])
        let store = DetailStore(item: item, details: NoDetails(), watch: WatchSpy([:]))
        await store.load()
        #expect(store.primaryPlay() == nil)
    }

    @Test func aNotDownloadedEpisodeRowCannotPlay() async {
        let item = show()
        let store = DetailStore(item: item, details: NoDetails(), watch: WatchSpy([:]))
        await store.load()

        let rows = store.episodes(forSeason: 2)
        let notDownloaded = DetailStore.EpisodeRowInfo(season: 2, number: 99, meta: nil, ownedEpisode: nil)
        #expect(store.episodePlayRequest(for: notDownloaded) == nil)

        let downloadedRow = rows.first { $0.number == 2 }!
        let request = store.episodePlayRequest(for: downloadedRow, fromStart: true)
        #expect(request?.label == "Show — S2·E2")
        #expect(request?.episode?.number == 2)
        #expect(request?.source == downloadedRow.ownedSource)
        #expect(request?.fromStart == true)
    }
}
