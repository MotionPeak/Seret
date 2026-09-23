import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

private final class ShowDetails: MediaDetailsProviding {
    let seasonCount: Int?
    let episodes: [Int: [TMDBEpisodeDetails]]
    init(seasonCount: Int?, episodes: [Int: [TMDBEpisodeDetails]]) {
        self.seasonCount = seasonCount; self.episodes = episodes
    }
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw FakeError.boom }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
        TMDBTVDetails(id: tmdbID, name: "Show", firstAirDate: "2011-04-17", overview: nil,
                      posterPath: nil, backdropPath: nil, numberOfSeasons: seasonCount,
                      genres: [], voteAverage: nil)
    }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] {
        episodes[season] ?? []
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
    func count() -> Int { rows.count }
}

private func meta(_ n: Int) -> TMDBEpisodeDetails {
    TMDBEpisodeDetails(episodeNumber: n, name: "E\(n)", overview: nil, stillPath: nil,
                       runtime: 50, airDate: nil)
}

private struct WatchFakeLibrary: LibraryProviding {
    let items: [MediaItem]
    func loadCached() -> [MediaItem]? { items }
    func refresh() async throws -> [MediaItem] { items }
    func remove(_ item: MediaItem) async throws {}
    func removeVersion(_ item: MediaItem, source: MediaSource) async throws {}
}

private func ownedMovie(_ id: String, tmdbID: Int) -> MediaItem {
    MediaItem(id: id, kind: .movie, title: "Movie", year: 2024,
             sources: [MediaSource(torrentID: "t", fileID: nil, restrictedLink: "l",
                                   parsed: ParsedRelease(title: "x"))],
             seasons: [], tmdbID: tmdbID)
}

@MainActor
@Suite struct TitleWatchToggleTests {
    private let hit = SearchHit(result: TMDBSearchResult(
        id: 603, title: "The Matrix", name: nil, releaseDate: "1999-03-31", firstAirDate: nil,
        posterPath: nil, overview: nil, voteAverage: nil), kind: .movie)
    private let showTitle = MediaItem(id: "show:tmdb:1399", kind: .show, title: "Game of Thrones",
                                      year: 2011, sources: [], seasons: [], tmdbID: 1399)

    @Test func aFilmYouDoNotOwnWritesOneRowUnderItsCanonicalKey() async {
        let watch = RecordingWatch()
        let toggle = TitleWatchToggle(watch: watch, showMarker: nil, library: nil, profileID: "p")

        let wrote = await toggle.set(true, title: .placeholder(for: hit))

        #expect(wrote)
        #expect(await watch.finished("movie:tmdb:603") == true)
        #expect(await watch.count() == 1)
    }

    @Test func anOwnedFilmGoesThroughTheLibrary() async {
        let watch = RecordingWatch()
        let owned = ownedMovie("movie:tmdb:603", tmdbID: 603)
        let library = LibraryStore(library: WatchFakeLibrary(items: [owned]), watch: watch,
                                   profileID: { "p" })
        await library.load()
        var changed = 0
        library.onContentChanged = { changed += 1 }
        let toggle = TitleWatchToggle(watch: watch, showMarker: nil, library: library, profileID: "p")

        let wrote = await toggle.set(true, title: owned)

        #expect(wrote)
        #expect(library.watchState(for: owned)?.finished == true)
        #expect(changed == 1)
    }

    @Test func aShowWritesTheSeriesKeyAndEveryEpisode() async {
        let watch = RecordingWatch()
        let details = ShowDetails(seasonCount: 2, episodes: [1: [meta(1), meta(2)], 2: [meta(1), meta(2)]])
        let marker = ShowWatchMarker(details: details, watch: watch)
        let owned = MediaItem(id: "show:tmdb:1399", kind: .show, title: "Game of Thrones",
                              year: 2011, sources: [], seasons: [], tmdbID: 1399)
        let library = LibraryStore(library: WatchFakeLibrary(items: [owned]), watch: watch,
                                   profileID: { "p" })
        await library.load()
        let toggle = TitleWatchToggle(watch: watch, showMarker: marker, library: library, profileID: "p")

        let wrote = await toggle.set(true, title: showTitle)

        #expect(wrote)
        #expect(await watch.count() == 5)   // series key + 2 + 2 episodes
        #expect(library.watchState(for: owned)?.finished == true)
    }

    @Test func unwatchingAShowClearsWhatWatchingWrote() async {
        let watch = RecordingWatch()
        let details = ShowDetails(seasonCount: 1, episodes: [1: [meta(1)]])
        let marker = ShowWatchMarker(details: details, watch: watch)
        let toggle = TitleWatchToggle(watch: watch, showMarker: marker, library: nil, profileID: "p")

        _ = await toggle.set(true, title: showTitle)
        _ = await toggle.set(false, title: showTitle)

        #expect(await watch.finished("show:tmdb:1399") == false)
        #expect(await watch.finished("show:tmdb:1399:s1e1") == false)
    }

    @Test func noProfileWritesNothing() async {
        let watch = RecordingWatch()
        let toggle = TitleWatchToggle(watch: watch, showMarker: nil, library: nil, profileID: nil)

        let wrote = await toggle.set(true, title: .placeholder(for: hit))

        #expect(!wrote)
        #expect(await watch.count() == 0)
    }
}
