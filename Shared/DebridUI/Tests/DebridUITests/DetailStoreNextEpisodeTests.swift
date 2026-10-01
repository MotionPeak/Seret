import Testing
import Foundation
import DebridCore
@testable import DebridUI

/// `nextEpisode()` scans EVERY season of a show, but the watch read only ever covered the SELECTED
/// one. An episode with no loaded state reads as "not finished", so seasons the viewer had never
/// opened on this visit all looked unwatched — and Play offered the first episode of the earliest
/// unvisited season instead of the one actually in progress.
@MainActor
@Suite struct DetailStoreNextEpisodeTests {

    private enum Boom: Error { case noDetails }

    private struct NoDetails: MediaDetailsProviding {
        func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw Boom.noDetails }
        func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw Boom.noDetails }
        func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
    }

    /// Reports every key it was asked for, so a test can prove the read covered all seasons.
    private actor WatchSpy: WatchProgressProviding {
        private let states: [String: WatchState]
        private(set) var requested: Set<String> = []
        init(_ states: [String: WatchState]) { self.states = states }

        func progress(forContentKey key: String, profileID: String) async throws -> WatchState? {
            requested.insert(key)
            return states[key]
        }
        func progress(forContentKeys keys: [String], profileID: String) async throws -> [String: WatchState] {
            requested.formUnion(keys)
            return states.filter { keys.contains($0.key) }
        }
        func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                    durationSeconds: Double, finished: Bool, profileID: String) async throws {}
        func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
        func deleteProgress(forContentKeys keys: [String]) async throws {}
    }

    private func src(_ id: String) -> MediaSource {
        MediaSource(torrentID: id, fileID: nil, restrictedLink: "rd://\(id)",
                    parsed: ParsedRelease(title: "t", resolution: "1080p"))
    }

    /// Three seasons, two episodes each. Seasons 1 and 2 are finished; S03E01 is mid-watch.
    private func threeSeasonShow() -> MediaItem {
        let seasons = (1...3).map { s in
            Season(number: s, episodes: (1...2).map { n in
                Episode(season: s, number: n, source: src("t\(s)-\(n)"))
            })
        }
        return MediaItem(id: "show:tmdb:200", kind: .show, title: "Show", year: 2020,
                         sources: [], seasons: seasons, tmdbID: 200)
    }

    private func finished(_ key: String) -> WatchState {
        WatchState(contentKey: key, sourceKey: "s", positionSeconds: 100, durationSeconds: 100,
                   finished: true, updatedAt: Date(timeIntervalSince1970: 1))
    }
    private func inProgress(_ key: String) -> WatchState {
        WatchState(contentKey: key, sourceKey: "s", positionSeconds: 300, durationSeconds: 3000,
                   finished: false, updatedAt: Date(timeIntervalSince1970: 2))
    }

    @Test func playResumesTheEpisodeInProgressInALaterSeason() async {
        let item = threeSeasonShow()
        var states: [String: WatchState] = [:]
        for s in 1...2 {
            for n in 1...2 {
                let k = WatchKey.content(forShow: item, season: s, number: n)
                states[k] = finished(k)
            }
        }
        let progressKey = WatchKey.content(forShow: item, season: 3, number: 1)
        states[progressKey] = inProgress(progressKey)

        let spy = WatchSpy(states)
        let store = DetailStore(item: item, details: NoDetails(), watch: spy)
        await store.load()

        let next = store.nextEpisode()
        #expect(next?.season == 3)
        #expect(next?.number == 1)
    }

    /// With every episode of seasons 1 and 2 finished and nothing started in season 3, Play must
    /// offer S03E01 — not S02E01, which only looked unwatched because it was never read.
    @Test func playOffersTheFirstGenuinelyUnwatchedEpisodeAcrossSeasons() async {
        let item = threeSeasonShow()
        var states: [String: WatchState] = [:]
        for s in 1...2 {
            for n in 1...2 {
                let k = WatchKey.content(forShow: item, season: s, number: n)
                states[k] = finished(k)
            }
        }

        let spy = WatchSpy(states)
        let store = DetailStore(item: item, details: NoDetails(), watch: spy)
        await store.load()

        let next = store.nextEpisode()
        #expect(next?.season == 3)
        #expect(next?.number == 1)
    }

    /// The read itself has to cover every owned episode, or the answer above is luck.
    @Test func theWatchReadCoversEveryOwnedEpisodeNotJustTheSelectedSeason() async {
        let item = threeSeasonShow()
        let spy = WatchSpy([:])
        let store = DetailStore(item: item, details: NoDetails(), watch: spy)
        await store.load()

        let expected = Set(item.seasons.flatMap { s in
            s.episodes.map { WatchKey.content(forShow: item, episode: $0) }
        })
        #expect(await spy.requested.isSuperset(of: expected))
    }

    /// TMDB details that succeed, so the show's load runs to the end — with the series' real length.
    private struct Details: MediaDetailsProviding {
        let seasons: Int
        func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw Boom.noDetails }
        func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
            TMDBTVDetails(id: 200, name: "Show", firstAirDate: "2020-01-01", overview: "o",
                          posterPath: nil, backdropPath: nil, numberOfSeasons: seasons,
                          genres: [], voteAverage: 8)
        }
        func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] {
            (1...2).map { TMDBEpisodeDetails(episodeNumber: $0, name: "E\($0)", overview: "o",
                                              stillPath: nil, runtime: 30, airDate: "2020-01-01") }
        }
    }

    private func state(_ key: String, finished: Bool, at t: TimeInterval) -> WatchState {
        WatchState(contentKey: key, sourceKey: "s", positionSeconds: finished ? 100 : 300,
                   durationSeconds: finished ? 100 : 3000, finished: finished,
                   updatedAt: Date(timeIntervalSince1970: t))
    }

    /// The FIRST part-way episode in series order used to win, so one abandoned at 89% weeks ago
    /// outranked the one being watched tonight — and Play dropped the viewer into its credits.
    @Test func theEpisodeWatchedMostRecentlyWinsOverAnOlderAbandonedOne() async {
        let item = threeSeasonShow()
        let old = WatchKey.content(forShow: item, season: 1, number: 2)
        let tonight = WatchKey.content(forShow: item, season: 3, number: 1)
        let store = DetailStore(item: item, details: NoDetails(),
                                watch: WatchSpy([old: state(old, finished: false, at: 1),
                                                 tonight: state(tonight, finished: false, at: 5)]))
        await store.load()
        #expect(store.nextEpisode()?.season == 3)
        #expect(store.nextEpisode()?.number == 1)
    }

    /// Only what you own was ever considered, so finishing the last episode you had offered
    /// "Play S1·E1" — though the next season was a press away.
    @Test func afterTheLastEpisodeYouOwnTheNextSeasonIsOffered() async {
        let s1 = (1...2).map { Episode(season: 1, number: $0, source: src("t1-\($0)")) }
        let item = MediaItem(id: "show:tmdb:200", kind: .show, title: "Show", year: 2020,
                             sources: [], seasons: [Season(number: 1, episodes: s1)], tmdbID: 200)
        let e1 = WatchKey.content(forShow: item, season: 1, number: 1)
        let e2 = WatchKey.content(forShow: item, season: 1, number: 2)
        let store = DetailStore(item: item, details: Details(seasons: 2),
                                watch: WatchSpy([e1: state(e1, finished: true, at: 1),
                                                 e2: state(e2, finished: true, at: 2)]))
        await store.load()
        #expect(store.nextEpisode() == nil)                       // not yours: Play fetches it…
        #expect(store.nextEpisodeTarget()?.season == 2)           // …and it is S2·E1, not S1·E1
        #expect(store.nextEpisodeTarget()?.number == 1)
    }

    /// The page opened on the first season you own, wherever you were.
    @Test func thePageOpensOnTheSeasonBeingWatched() async {
        let item = threeSeasonShow()
        let key = WatchKey.content(forShow: item, season: 3, number: 1)
        let store = DetailStore(item: item, details: Details(seasons: 3),
                                watch: WatchSpy([key: state(key, finished: false, at: 5)]))
        #expect(store.selectedSeason == 1)
        await store.load()
        #expect(store.selectedSeason == 3)
    }

    /// A show with nothing watched still starts at the beginning.
    @Test func anUnwatchedShowStartsAtTheFirstEpisode() async {
        let item = threeSeasonShow()
        let store = DetailStore(item: item, details: NoDetails(), watch: WatchSpy([:]))
        await store.load()
        let next = store.nextEpisode()
        #expect(next?.season == 1)
        #expect(next?.number == 1)
    }
}
