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
    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { rows[key] }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws {
        rows[contentKey] = WatchState(contentKey: contentKey, sourceKey: sourceKey,
                                      positionSeconds: positionSeconds, durationSeconds: durationSeconds,
                                      finished: finished, updatedAt: Date(timeIntervalSince1970: 0))
    }
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] {
        Array(rows.values.filter { !$0.finished && $0.positionSeconds > 0 }.prefix(limit))
    }
    func deleteProgress(forContentKeys keys: [String]) async throws {
        for k in keys { rows[k] = nil }
    }
}

private actor FakeMyList: MyListProviding {
    private var claimed: Set<String> = []
    init(_ seed: Set<String> = []) { claimed = seed }
    func claim(profileID: String, contentKey: String) async throws { claimed.insert("\(profileID)|\(contentKey)") }
    func unclaim(profileID: String, contentKey: String) async throws { claimed.remove("\(profileID)|\(contentKey)") }
    func isClaimed(profileID: String, contentKey: String) async throws -> Bool { claimed.contains("\(profileID)|\(contentKey)") }
    func contentKeys(forProfile profileID: String) async throws -> [String] {
        claimed.filter { $0.hasPrefix("\(profileID)|") }.map { String($0.dropFirst(profileID.count + 1)) }
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

    @Test func toggleMyListClaimsThenUnclaims() async {
        let m = movie("1", sources: [source("t", "1080p")])
        let key = WatchKey.content(forMovie: m)
        let list = FakeMyList()
        let store = DetailStore(item: m, details: FakeDetails(movie: .success(movieDetails())),
                                watch: nil, profileID: "p1", myList: list)
        await store.loadMyList(contentKey: key)
        #expect(store.inMyList == false)
        await store.toggleMyList(contentKey: key)
        #expect(store.inMyList == true)
        #expect((try? await list.isClaimed(profileID: "p1", contentKey: key)) == true)
        await store.toggleMyList(contentKey: key)
        #expect(store.inMyList == false)
    }

    @Test func markWatchedWritesAndReadsBack() async {
        let m = movie("1", sources: [source("t", "1080p")])
        let store = DetailStore(item: m, details: FakeDetails(movie: .success(movieDetails())),
                                watch: FakeWatch(), profileID: "p1")
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
                                watch: FakeWatch([key: seeded]), profileID: "p1")
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
                                watch: FakeWatch([key: seeded]), profileID: "p1")
        await store.load()
        #expect(store.playRequest(source: m.sources[0], episode: nil, label: m.title).resumeAt == nil)
    }

    // MARK: - All seasons / not-downloaded episodes

    private func tv(seasons: Int) -> TMDBTVDetails {
        TMDBTVDetails(id: 200, name: "Show", firstAirDate: "2020-01-01", overview: "o",
                      posterPath: "/p.jpg", backdropPath: "/b.jpg", numberOfSeasons: seasons,
                      genres: [], voteAverage: 8.0)
    }
    private func tmdbEp(_ n: Int) -> TMDBEpisodeDetails {
        TMDBEpisodeDetails(episodeNumber: n, name: "E\(n)", overview: "o", stillPath: nil,
                           runtime: 30, airDate: nil)
    }

    @Test func allSeasonsCoversTMDBCountNotJustOwned() async {
        // Owns only season 2; TMDB says there are 3 seasons → picker should offer 1, 2, 3.
        let sh = show("9", seasons: [Season(number: 2, episodes: [episode(2, 1, "t1")])])
        let store = DetailStore(item: sh,
                                details: FakeDetails(tv: .success(tv(seasons: 3)),
                                                     seasons: [2: .success([tmdbEp(1), tmdbEp(2)])]),
                                watch: nil)
        #expect(store.allSeasons == [2])          // before load: only the owned season
        await store.load()
        #expect(store.allSeasons == [1, 2, 3])    // after load: every TMDB season
    }

    @Test func episodesForSeasonMergesTMDBWithOwnedAndFlagsNotDownloaded() async {
        // Owns S2E1 only; TMDB season 2 has E1, E2, E3 → E1 downloaded, E2/E3 not.
        let sh = show("9", seasons: [Season(number: 2, episodes: [episode(2, 1, "t1")])])
        let store = DetailStore(item: sh,
                                details: FakeDetails(tv: .success(tv(seasons: 3)),
                                                     seasons: [2: .success([tmdbEp(1), tmdbEp(2), tmdbEp(3)])]),
                                watch: nil)
        await store.load()
        let rows = store.episodes(forSeason: 2)
        #expect(rows.map(\.number) == [1, 2, 3])
        #expect(rows[0].isDownloaded == true)
        #expect(rows[0].ownedEpisode?.source.torrentID == "t1")
        #expect(rows[1].isDownloaded == false)
        #expect(rows[2].isDownloaded == false)
        #expect(rows[1].meta?.name == "E2")       // not-downloaded rows still carry TMDB metadata
    }

    @Test func episodesForUnownedSeasonAreAllNotDownloaded() async {
        let sh = show("9", seasons: [Season(number: 2, episodes: [episode(2, 1, "t1")])])
        let store = DetailStore(item: sh,
                                details: FakeDetails(tv: .success(tv(seasons: 3)),
                                                     seasons: [1: .success([tmdbEp(1), tmdbEp(2)])]),
                                watch: nil)
        await store.load()
        await store.selectSeason(1)               // a season the user owns nothing in
        let rows = store.episodes(forSeason: 1)
        #expect(rows.map(\.number) == [1, 2])
        #expect(rows.allSatisfy { !$0.isDownloaded })
    }

    // MARK: - Batched watch reads / fromStart / reloadWatch

    @Test func playRequestCarriesTheExplicitFromStartIntent() async {
        let m = movie("1", sources: [source("t", "1080p")])
        let store = DetailStore(item: m, details: FakeDetails(movie: .success(movieDetails())), watch: nil)
        #expect(store.playRequest(source: m.sources[0], episode: nil, label: m.title,
                                  fromStart: true).fromStart == true)
        #expect(store.playRequest(source: m.sources[0], episode: nil, label: m.title).fromStart == false)
    }

    @Test func seasonWatchStateLoadsThroughTheBatchedRead() async {
        // A provider with a real batch implementation must be hit ONCE for the whole season —
        // proving the seam dispatches to the batch method (WatchProgressStore's single fetch),
        // not the per-key default.
        let e1 = episode(1, 1, "t1"), e2 = episode(1, 2, "t2")
        let sh = show("9", seasons: [Season(number: 1, episodes: [e1, e2])])
        let e1Key = WatchKey.content(forShow: sh, episode: e1)
        let watch = BatchingFakeWatch([e1Key: WatchState(contentKey: e1Key, sourceKey: "s",
                                                         positionSeconds: 300, durationSeconds: 1200,
                                                         finished: false,
                                                         updatedAt: Date(timeIntervalSince1970: 0))])
        let store = DetailStore(item: sh,
                                details: FakeDetails(tv: .success(tvDetails()), seasons: [:]),
                                watch: watch, profileID: "p1")
        await store.load()
        #expect(store.watchState(forKey: e1Key)?.positionSeconds == 300)
        #expect(await watch.batchCalls == 1)          // one batched read for the season
        #expect(await watch.singleCalls == 0)         // never fell back to per-key reads
    }

    @Test func reloadWatchPicksUpProgressRecordedSincePlayback() async {
        let m = movie("1", sources: [source("t", "1080p")])
        let key = WatchKey.content(forMovie: m)
        let watch = FakeWatch()
        let store = DetailStore(item: m, details: FakeDetails(movie: .success(movieDetails())),
                                watch: watch, profileID: "p1")
        await store.load()
        #expect(store.watchState(forKey: key) == nil)
        // The player recorded progress while this screen sat behind the cover…
        try? await watch.record(contentKey: key, sourceKey: "s", positionSeconds: 480,
                                durationSeconds: 1200, finished: false, profileID: "p1")
        await store.reloadWatch()
        #expect(store.watchState(forKey: key)?.positionSeconds == 480)   // …and the label follows
    }
}

/// A watch fake with a REAL batch implementation + call counters, to assert protocol dispatch.
private actor BatchingFakeWatch: WatchProgressProviding {
    private var rows: [String: WatchState]
    private(set) var batchCalls = 0
    private(set) var singleCalls = 0
    init(_ seed: [String: WatchState] = [:]) { rows = seed }
    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? {
        singleCalls += 1
        return rows[key]
    }
    func progress(forContentKeys keys: [String], profileID: String) async throws -> [String: WatchState] {
        batchCalls += 1
        return rows.filter { keys.contains($0.key) }
    }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws {}
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
    func deleteProgress(forContentKeys keys: [String]) async throws {}
}
