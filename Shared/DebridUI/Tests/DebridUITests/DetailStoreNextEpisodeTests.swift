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
