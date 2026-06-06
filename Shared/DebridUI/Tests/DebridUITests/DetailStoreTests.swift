import Testing
import Foundation
import DebridCore
@testable import DebridUI

// MARK: - Fixtures

private func parsed(_ res: String?) -> ParsedRelease { ParsedRelease(title: "t", resolution: res) }
private func source(_ id: String, _ res: String?) -> MediaSource {
    MediaSource(torrentID: id, fileID: nil, restrictedLink: "https://rd/\(id)", parsed: parsed(res))
}
private func movie(_ id: String, tmdb: Int? = 100, sources: [MediaSource]) -> MediaItem {
    MediaItem(id: id, kind: .movie, title: "Movie \(id)", year: 2024, sources: sources, seasons: [], tmdbID: tmdb)
}
private func show(_ id: String, tmdb: Int? = 200, seasons: [Season]) -> MediaItem {
    MediaItem(id: id, kind: .show, title: "Show \(id)", year: 2020, sources: [], seasons: seasons, tmdbID: tmdb)
}
private func episode(_ s: Int, _ n: Int, _ torrent: String) -> Episode {
    Episode(season: s, number: n, source: source(torrent, "1080p"))
}
private func movieDetails() -> TMDBMovieDetails {
    TMDBMovieDetails(id: 100, title: "Movie", releaseDate: "2024-01-01", overview: "Rich overview",
                     posterPath: "/p.jpg", backdropPath: "/b.jpg", runtime: 120,
                     genres: [TMDBGenre(id: 1, name: "Action")], voteAverage: 7.0)
}
private func tvDetails() -> TMDBTVDetails {
    TMDBTVDetails(id: 200, name: "Show", firstAirDate: "2020-01-01", overview: "Show overview",
                  posterPath: "/p.jpg", backdropPath: "/tb.jpg", numberOfSeasons: 1,
                  genres: [TMDBGenre(id: 18, name: "Drama")], voteAverage: 8.0)
}

private enum FakeError: Error { case boom }

private final class FakeDetails: MediaDetailsProviding {
    let movie: Result<TMDBMovieDetails, FakeError>
    let tv: Result<TMDBTVDetails, FakeError>
    let seasons: [Int: Result<[TMDBEpisodeDetails], FakeError>]
    init(movie: Result<TMDBMovieDetails, FakeError> = .failure(.boom),
         tv: Result<TMDBTVDetails, FakeError> = .failure(.boom),
         seasons: [Int: Result<[TMDBEpisodeDetails], FakeError>] = [:]) {
        self.movie = movie; self.tv = tv; self.seasons = seasons
    }
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { try movie.get() }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { try tv.get() }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] {
        try (seasons[season] ?? .success([])).get()
    }
}

private actor FakeWatch: WatchProgressProviding {
    private var rows: [String: WatchState]
    init(_ seed: [String: WatchState] = [:]) { rows = seed }
    func progress(forContentKey key: String) async throws -> WatchState? { rows[key] }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool) async throws {
        rows[contentKey] = WatchState(contentKey: contentKey, sourceKey: sourceKey,
                                      positionSeconds: positionSeconds, durationSeconds: durationSeconds,
                                      finished: finished, updatedAt: Date(timeIntervalSince1970: 0))
    }
    func recentlyWatched(limit: Int) async throws -> [WatchState] {
        Array(rows.values.filter { !$0.finished && $0.positionSeconds > 0 }.prefix(limit))
    }
}

// MARK: - Tests

@MainActor
@Suite struct DetailStoreTests {
    @Test func movieBaseThenRichFills() async {
        let m = movie("1", sources: [source("t", "1080p")])
        let store = DetailStore(item: m, details: FakeDetails(movie: .success(movieDetails())), watch: nil)
        #expect(store.richState == .idle)              // nothing fetched yet
        await store.load()
        #expect(store.richState == .loaded)
        #expect(store.backdropPath == "/b.jpg")
        #expect(store.runtime == 120)
        #expect(store.genres == ["Action"])
        #expect(store.overview == "Rich overview")
    }

    @Test func movieRichFailureKeepsBase() async {
        let m = MediaItem(id: "1", kind: .movie, title: "Movie 1", year: 2024,
                          sources: [source("t", "1080p")], seasons: [], tmdbID: 100,
                          overview: "Base overview")
        let store = DetailStore(item: m, details: FakeDetails(movie: .failure(.boom)), watch: nil)
        await store.load()
        #expect(store.richState == .failed)
        #expect(store.runtime == nil)                 // never set on the failed path
        #expect(store.overview == "Base overview")    // base info preserved through the failure
    }

    @Test func noTMDBIDSkipsFetchStaysLoaded() async {
        let m = movie("1", tmdb: nil, sources: [source("t", "1080p")])
        let store = DetailStore(item: m, details: FakeDetails(), watch: nil)
        await store.load()
        #expect(store.richState == .loaded)
    }

    @Test func versionsBestFirstAndBestIsTop() {
        let m = movie("1", sources: [source("a", "720p"), source("b", "2160p"), source("c", "1080p")])
        let store = DetailStore(item: m, details: FakeDetails(), watch: nil)
        #expect(store.versions.map(\.torrentID) == ["b", "c", "a"])
        #expect(store.bestSource?.torrentID == "b")
    }

    @Test func showLoadsSelectedSeasonEpisodes() async {
        let sh = show("9", seasons: [Season(number: 1, episodes: [episode(1, 1, "t1"), episode(1, 2, "t2")])])
        let eps = [TMDBEpisodeDetails(episodeNumber: 1, name: "Pilot", overview: "o",
                                      stillPath: "/s.jpg", runtime: 50, airDate: "2020-01-01")]
        let store = DetailStore(item: sh,
                                details: FakeDetails(tv: .success(tvDetails()), seasons: [1: .success(eps)]),
                                watch: nil)
        await store.load()
        #expect(store.richState == .loaded)
        #expect(store.selectedSeason == 1)
        #expect(store.episodeMeta[1]?[1]?.name == "Pilot")
    }

    @Test func markWatchedWritesAndReadsBack() async {
        let m = movie("1", sources: [source("t", "1080p")])
        let store = DetailStore(item: m, details: FakeDetails(movie: .success(movieDetails())), watch: FakeWatch())
        await store.load()
        let key = WatchKey.content(forMovie: m)
        #expect(store.watchState(forKey: key) == nil)
        await store.setWatched(true, contentKey: key, source: m.sources[0])
        #expect(store.watchState(forKey: key)?.finished == true)
        await store.setWatched(false, contentKey: key, source: m.sources[0])
        #expect(store.watchState(forKey: key)?.finished == false)
    }

    @Test func resumeReflectedInPlayRequest() async {
        let m = movie("1", sources: [source("t", "1080p")])
        let key = WatchKey.content(forMovie: m)
        let seeded = WatchState(contentKey: key, sourceKey: WatchKey.source(m.sources[0]),
                                positionSeconds: 600, durationSeconds: 1200, finished: false,
                                updatedAt: Date(timeIntervalSince1970: 0))
        let store = DetailStore(item: m, details: FakeDetails(movie: .success(movieDetails())),
                                watch: FakeWatch([key: seeded]))
        await store.load()
        #expect(store.playRequest(source: m.sources[0], episode: nil, label: m.title).resumeAt == 600)
        #expect(store.playRequest(source: m.sources[0], episode: nil, label: m.title, fromStart: true).resumeAt == nil)
    }

    @Test func finishedDoesNotResume() async {
        let m = movie("1", sources: [source("t", "1080p")])
        let key = WatchKey.content(forMovie: m)
        let seeded = WatchState(contentKey: key, sourceKey: WatchKey.source(m.sources[0]),
                                positionSeconds: 1200, durationSeconds: 1200, finished: true,
                                updatedAt: Date(timeIntervalSince1970: 0))
        let store = DetailStore(item: m, details: FakeDetails(movie: .success(movieDetails())),
                                watch: FakeWatch([key: seeded]))
        await store.load()
        #expect(store.playRequest(source: m.sources[0], episode: nil, label: m.title).resumeAt == nil)
    }
}
