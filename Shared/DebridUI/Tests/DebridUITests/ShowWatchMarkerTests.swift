import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

private final class ShowDetails: MediaDetailsProviding {
    let seasonCount: Int?
    let episodes: [Int: [TMDBEpisodeDetails]]
    let failSeason: Int?
    init(seasonCount: Int?, episodes: [Int: [TMDBEpisodeDetails]], failSeason: Int? = nil) {
        self.seasonCount = seasonCount; self.episodes = episodes; self.failSeason = failSeason
    }
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw FakeError.boom }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
        TMDBTVDetails(id: tmdbID, name: "Show", firstAirDate: "2011-04-17", overview: nil,
                      posterPath: nil, backdropPath: nil, numberOfSeasons: seasonCount,
                      genres: [], voteAverage: nil)
    }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] {
        if season == failSeason { throw FakeError.boom }
        return episodes[season] ?? []
    }
}

private actor RecordingWatch: WatchProgressProviding {
    private(set) var rows: [String: WatchState] = [:]
    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { rows[key] }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws {
        rows[contentKey] = WatchState(contentKey: contentKey, sourceKey: sourceKey,
                                      positionSeconds: positionSeconds,
                                      durationSeconds: durationSeconds, finished: finished,
                                      updatedAt: Date(timeIntervalSince1970: 0))
    }
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
    func deleteProgress(forContentKeys keys: [String]) async throws {}
    func keys() -> Set<String> { Set(rows.keys) }
    func finished(_ key: String) -> Bool? { rows[key]?.finished }
}

private func meta(_ n: Int) -> TMDBEpisodeDetails {
    TMDBEpisodeDetails(episodeNumber: n, name: "E\(n)", overview: nil, stillPath: nil,
                       runtime: 50, airDate: nil)
}

@MainActor
@Suite struct ShowWatchMarkerTests {
    private let show = MediaItem(id: "show:tmdb:1399", kind: .show, title: "Game of Thrones",
                                 year: 2011, sources: [], seasons: [], tmdbID: 1399)

    @Test func marksEveryEpisodeOfEverySeason() async {
        let watch = RecordingWatch()
        let details = ShowDetails(seasonCount: 2, episodes: [1: [meta(1), meta(2)], 2: [meta(1)]])
        let marker = ShowWatchMarker(details: details, watch: watch)

        await marker.mark(true, show: show, profileID: "")

        let keys = await watch.keys()
        #expect(keys.contains("show:tmdb:1399:s1e1"))
        #expect(keys.contains("show:tmdb:1399:s1e2"))
        #expect(keys.contains("show:tmdb:1399:s2e1"))
        #expect(await watch.finished("show:tmdb:1399:s1e2") == true)
    }

    @Test func alsoMarksTheSeriesItself() async {
        let watch = RecordingWatch()
        let details = ShowDetails(seasonCount: 1, episodes: [1: [meta(1)]])
        let marker = ShowWatchMarker(details: details, watch: watch)

        await marker.mark(true, show: show, profileID: "")

        // The poster's tick reads the series key; without it a marked show looks unmarked.
        #expect(await watch.finished("show:tmdb:1399") == true)
    }

    @Test func unmarkingClearsEveryEpisodeAndTheSeries() async {
        let watch = RecordingWatch()
        let details = ShowDetails(seasonCount: 1, episodes: [1: [meta(1), meta(2)]])
        let marker = ShowWatchMarker(details: details, watch: watch)

        await marker.mark(true, show: show, profileID: "")
        await marker.mark(false, show: show, profileID: "")

        #expect(await watch.finished("show:tmdb:1399:s1e1") == false)
        #expect(await watch.finished("show:tmdb:1399:s1e2") == false)
        #expect(await watch.finished("show:tmdb:1399") == false)
    }

    @Test func aSeasonThatFailsDoesNotStopTheRest() async {
        let watch = RecordingWatch()
        let details = ShowDetails(seasonCount: 2, episodes: [1: [meta(1)], 2: [meta(1)]],
                                  failSeason: 1)
        let marker = ShowWatchMarker(details: details, watch: watch)

        await marker.mark(true, show: show, profileID: "")

        #expect(await watch.finished("show:tmdb:1399:s2e1") == true)
        #expect(await watch.finished("show:tmdb:1399:s1e1") == nil)
    }

    @Test func aShowWithNoSeasonCountStillMarksTheSeries() async {
        let watch = RecordingWatch()
        let marker = ShowWatchMarker(details: ShowDetails(seasonCount: nil, episodes: [:]),
                                     watch: watch)

        await marker.mark(true, show: show, profileID: "")

        #expect(await watch.finished("show:tmdb:1399") == true)
    }

    @Test func aMovieIsNotAShow() async {
        let watch = RecordingWatch()
        let movie = MediaItem(id: "movie:tmdb:70160", kind: .movie, title: "M", year: 2012,
                              sources: [], seasons: [], tmdbID: 70160)
        let marker = ShowWatchMarker(details: ShowDetails(seasonCount: 2, episodes: [1: [meta(1)]]),
                                     watch: watch)

        await marker.mark(true, show: movie, profileID: "")

        #expect(await watch.keys().isEmpty)
    }
}
