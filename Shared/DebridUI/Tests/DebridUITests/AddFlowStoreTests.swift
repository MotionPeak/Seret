import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

private final class FakeDetails: MediaDetailsProviding {
    let movie: Result<TMDBMovieDetails, FakeError>
    let tv: Result<TMDBTVDetails, FakeError>
    let episodes: [Int: Result<[TMDBEpisodeDetails], FakeError>]
    init(movie: Result<TMDBMovieDetails, FakeError> = .failure(.boom),
         tv: Result<TMDBTVDetails, FakeError> = .failure(.boom),
         episodes: [Int: Result<[TMDBEpisodeDetails], FakeError>] = [:]) {
        self.movie = movie; self.tv = tv; self.episodes = episodes
    }
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { try movie.get() }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { try tv.get() }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] {
        try (episodes[season] ?? .success([])).get()
    }
}

/// Per-season gates so a test can dictate which in-flight season fetch completes first.
private actor SeasonGates {
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var opened: Set<Int> = []
    func wait(_ season: Int) async {
        if opened.contains(season) { return }
        await withCheckedContinuation { waiters[season] = $0 }
    }
    func open(_ season: Int) {
        opened.insert(season)
        waiters.removeValue(forKey: season)?.resume()
    }
}

/// Details provider whose season fetches park on `gates` until the test opens them.
private final class GatedDetails: MediaDetailsProviding, Sendable {
    let gates = SeasonGates()
    private let tv: TMDBTVDetails
    init(tv: TMDBTVDetails) { self.tv = tv }
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw FakeError.boom }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { tv }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] {
        await gates.wait(season)
        return [TMDBEpisodeDetails(episodeNumber: 1, name: "S\(season)E1", overview: nil,
                                   stillPath: nil, runtime: nil, airDate: nil)]
    }
}

private final class FakeStreamSource: StreamSource {
    let result: Result<[CachedStream], FakeError>
    init(_ result: Result<[CachedStream], FakeError>) { self.result = result }
    func streams(for query: StreamQuery) async throws -> [CachedStream] { try result.get() }
}

private final class FakeAdd: AddProviding {
    let result: Result<TorrentInfo, FakeError>
    init(_ result: Result<TorrentInfo, FakeError> = .failure(.boom)) { self.result = result }
    func add(infoHash: String) async throws -> TorrentInfo { try result.get() }
}

private func cachedStream(_ hash: String, res: String, langs: [String], size: Int) -> CachedStream {
    CachedStream(infoHash: hash, fileIdx: nil, rawTitle: "t",
                 parsed: ParsedRelease(title: "t", resolution: res),
                 languages: langs, sizeBytes: size, sourceName: nil)
}

private func downloadedInfo() -> TorrentInfo {
    TorrentInfo(id: "T1", filename: "Movie.2024.2160p.mkv", hash: "h", bytes: 9, progress: 100,
                status: "downloaded",
                files: [TorrentFile(id: 1, path: "/Movie/Movie.2024.2160p.mkv", bytes: 9, selected: 1)],
                links: ["https://rd/d/X"])
}

private func movieDetails(imdb: String?) -> TMDBMovieDetails {
    TMDBMovieDetails(id: 11, title: "Movie", releaseDate: "2024-01-01", overview: "o",
                     posterPath: "/p.jpg", backdropPath: "/b.jpg", runtime: 120, genres: [],
                     voteAverage: 8, originalLanguage: "fr", imdbID: imdb)
}

private func tvDetails(imdb: String?, seasons: Int?) -> TMDBTVDetails {
    TMDBTVDetails(id: 22, name: "Show", firstAirDate: "2020-01-01", overview: "o",
                  posterPath: "/p.jpg", backdropPath: "/b.jpg", numberOfSeasons: seasons,
                  genres: [], voteAverage: 9, originalLanguage: "en", imdbID: imdb)
}

private func episode(_ n: Int) -> TMDBEpisodeDetails {
    TMDBEpisodeDetails(episodeNumber: n, name: "E\(n)", overview: nil, stillPath: nil,
                       runtime: 50, airDate: nil)
}

private func movieHit() -> SearchHit {
    SearchHit(result: TMDBSearchResult(id: 11, title: "Movie", name: nil, releaseDate: "2024-01-01",
                                       firstAirDate: nil, posterPath: "/p.jpg", overview: "o",
                                       voteAverage: 8), kind: .movie)
}

private func showHit() -> SearchHit {
    SearchHit(result: TMDBSearchResult(id: 22, title: nil, name: "Show", releaseDate: nil,
                                       firstAirDate: "2020-01-01", posterPath: "/p.jpg", overview: "o",
                                       voteAverage: 9), kind: .show)
}

@MainActor
@Suite struct AddFlowStoreTests {
    private func flow(hit: SearchHit, details: FakeDetails,
                      streams: Result<[CachedStream], FakeError> = .success([]),
                      add: Result<TorrentInfo, FakeError> = .failure(.boom)) -> AddFlowStore {
        AddFlowStore(hit: hit, details: details,
                     streamSource: FakeStreamSource(streams), add: FakeAdd(add))
    }

    @Test func movieResolveLoadsBestInOriginalLanguage() async {
        let f = flow(hit: movieHit(), details: FakeDetails(movie: .success(movieDetails(imdb: "tt1"))),
                     streams: .success([
                        cachedStream("a", res: "2160p", langs: ["en"], size: 100),
                        cachedStream("b", res: "1080p", langs: ["fr"], size: 50)]))
        await f.resolve()
        #expect(f.phase == .movie)
        #expect(f.title == "Movie")
        #expect(f.add?.state == .streams)
        #expect(f.add?.best?.infoHash == "b")   // fr = original language
        #expect(f.add?.isFallback == false)
    }

    @Test func movieResolveFailsWhenNoIMDB() async {
        let f = flow(hit: movieHit(), details: FakeDetails(movie: .success(movieDetails(imdb: nil))))
        await f.resolve()
        if case .resolveFailed = f.phase {} else { Issue.record("expected resolveFailed") }
    }

    @Test func movieResolveFailsWhenDetailsThrow() async {
        let f = flow(hit: movieHit(), details: FakeDetails(movie: .failure(.boom)))
        await f.resolve()
        if case .resolveFailed = f.phase {} else { Issue.record("expected resolveFailed") }
    }

    @Test func showResolvePopulatesSeasonsAndFirstSeasonEpisodes() async {
        let f = flow(hit: showHit(),
                     details: FakeDetails(tv: .success(tvDetails(imdb: "tt9", seasons: 2)),
                                          episodes: [1: .success([episode(1), episode(2)])]))
        await f.resolve()
        #expect(f.phase == .show)
        #expect(f.seasons == [1, 2])
        #expect(f.selectedSeason == 1)
        #expect(f.episodes.count == 2)
        #expect(f.add == nil)   // nothing loaded until an episode is picked
    }

    @Test func showSelectEpisodeLoadsStreams() async {
        let f = flow(hit: showHit(),
                     details: FakeDetails(tv: .success(tvDetails(imdb: "tt9", seasons: 1)),
                                          episodes: [1: .success([episode(1)])]),
                     streams: .success([cachedStream("z", res: "1080p", langs: ["en"], size: 10)]))
        await f.resolve()
        await f.selectEpisode(1)
        #expect(f.selectedEpisode == 1)
        #expect(f.add?.state == .streams)
        #expect(f.add?.best?.infoHash == "z")
    }

    @Test func playbackRequestBuiltFromAddedInfo() async {
        let f = flow(hit: movieHit(), details: FakeDetails(movie: .success(movieDetails(imdb: "tt1"))),
                     streams: .success([cachedStream("b", res: "1080p", langs: ["fr"], size: 50)]),
                     add: .success(downloadedInfo()))
        await f.resolve()
        await f.addBest()
        guard case let .added(info) = f.add?.state else { Issue.record("expected added"); return }
        let request = f.playbackRequest(from: info)
        #expect(request?.item.title == "Movie")
        #expect(request?.label == "Movie")
        #expect(request?.source.restrictedLink == "https://rd/d/X")
        #expect(request?.item.tmdbID == 11)
    }

    @Test func selectSeasonRaceKeepsTheSelectedSeasonsEpisodes() async {
        // tvOS season pills switch on FOCUS — gliding 1→3 fires overlapping selectSeason calls.
        // Whichever TMDB fetch lands LAST must not overwrite the selected season's episodes.
        let details = GatedDetails(tv: tvDetails(imdb: "tt9", seasons: 3))
        await details.gates.open(1)                       // resolve()'s auto-select finishes normally
        let f = AddFlowStore(hit: showHit(), details: details,
                             streamSource: FakeStreamSource(.success([])), add: FakeAdd())
        await f.resolve()
        #expect(f.selectedSeason == 1)
        #expect(f.episodes.first?.name == "S1E1")

        let t2 = Task { await f.selectSeason(2) }         // in flight, parked on its gate
        try? await Task.sleep(nanoseconds: 20_000_000)
        let t3 = Task { await f.selectSeason(3) }         // the season the user settled on
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(f.selectedSeason == 3)
        #expect(f.episodes.isEmpty)                       // loading → skeletons, not season 1's cards

        await details.gates.open(3)                       // the CURRENT season lands first…
        try? await Task.sleep(nanoseconds: 40_000_000)
        #expect(f.episodes.first?.name == "S3E1")

        await details.gates.open(2)                       // …then the STALE fetch finishes last
        _ = await t2.value
        _ = await t3.value
        #expect(f.selectedSeason == 3)
        #expect(f.episodes.first?.name == "S3E1")         // stale season 2 must NOT overwrite
    }

    @Test func selectingASeasonPreparesAndDownloadsTheSeasonPack() async {
        let pack = CachedStream(infoHash: "pack", fileIdx: nil, rawTitle: "Show.S01.2160p",
                                parsed: ParsedRelease(title: "Show", season: 1, episode: nil, resolution: "2160p"),
                                languages: ["en"], sizeBytes: 1, sourceName: nil)
        let loneEpisode = cachedStream("ep", res: "1080p", langs: ["en"], size: 1)  // no season → not a pack
        let f = flow(hit: showHit(),
                     details: FakeDetails(tv: .success(tvDetails(imdb: "tt9", seasons: 1)),
                                          episodes: [1: .success([episode(1)])]),
                     streams: .success([pack, loneEpisode]),
                     add: .success(downloadedInfo()))
        await f.resolve()                              // resolveShow auto-selects season 1
        #expect(f.seasonAdd?.state == .streams)
        #expect(f.seasonAdd?.best?.infoHash == "pack") // only the full-season pack, not the single episode
        await f.addSeason()
        if case .added = f.seasonAdd?.state {} else { Issue.record("expected the season pack to be added") }
    }
}
