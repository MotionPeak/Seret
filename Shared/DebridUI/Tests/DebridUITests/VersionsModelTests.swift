import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

// MARK: - Fixtures (mirrors AddFlowStoreTests / TitleAcquirerTests)

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

private func movieDetails(imdb: String?) -> TMDBMovieDetails {
    TMDBMovieDetails(id: 11, title: "Movie", releaseDate: "2024-01-01", overview: "o",
                     posterPath: "/p.jpg", backdropPath: "/b.jpg", runtime: 120, genres: [],
                     voteAverage: 8, originalLanguage: "en", imdbID: imdb)
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

/// A cached (instant) stream, roughly 2160p sized so `splitOversized` leaves it in "rest".
private func cachedStream(_ hash: String, res: String = "1080p", size: Int = 5_000_000_000) -> CachedStream {
    CachedStream(infoHash: hash, fileIdx: nil, rawTitle: "Movie.2024.\(res)",
                parsed: ParsedRelease(title: "Movie", resolution: res), languages: ["en"],
                sizeBytes: size, sourceName: nil, isCached: true)
}

/// An oversized 2160p release — over the 35 GB band, so `splitOversized` puts it in "larger".
private func oversizedStream(_ hash: String) -> CachedStream {
    CachedStream(infoHash: hash, fileIdx: nil, rawTitle: "Movie.2024.2160p.REMUX",
                parsed: ParsedRelease(title: "Movie", resolution: "2160p", source: "REMUX"),
                languages: ["en"], sizeBytes: 60_000_000_000, sourceName: nil, isCached: true)
}

private final class FakeStreamSource: StreamSource {
    let result: Result<[CachedStream], FakeError>
    init(_ result: Result<[CachedStream], FakeError> = .success([])) { self.result = result }
    func streams(for query: StreamQuery) async throws -> [CachedStream] { try result.get() }
}

/// Records the `StreamQuery.Kind` of every call — proves an episode target queries per
/// `series(season:episode:)` rather than the whole show.
private final class RecordingStreamSource: StreamSource, @unchecked Sendable {
    private(set) var kinds: [StreamQuery.Kind] = []
    let result: [CachedStream]
    init(_ result: [CachedStream] = []) { self.result = result }
    func streams(for query: StreamQuery) async throws -> [CachedStream] {
        kinds.append(query.kind)
        return result
    }
}

private final class FakeAdd: AddProviding, @unchecked Sendable {
    let result: Result<TorrentInfo, FakeError>
    init(_ result: Result<TorrentInfo, FakeError> = .failure(.boom)) { self.result = result }
    func add(infoHash: String) async throws -> TorrentInfo { try result.get() }
}

private func downloadedInfo() -> TorrentInfo {
    TorrentInfo(id: "T1", filename: "Movie.2024.1080p.mkv", hash: "h", bytes: 9, progress: 100,
               status: "downloaded",
               files: [TorrentFile(id: 1, path: "/Movie/Movie.2024.1080p.mkv", bytes: 9, selected: 1)],
               links: ["https://rd/d/X"])
}

// MARK: - Download-store fakes (mirrors TitleAcquirerTests)

private final class FakeReq: DownloadRequesting, @unchecked Sendable {
    let result: Result<TorrentInfo, FakeError>
    init(_ result: Result<TorrentInfo, FakeError> = .success(downloadedInfo())) { self.result = result }
    func startDownload(infoHash: String) async throws -> TorrentInfo { try result.get() }
}
private final class FakeRecords: DownloadRecording, @unchecked Sendable {
    func upsert(_ data: DownloadRequestData) async throws {}
    func all() async throws -> [DownloadRequestData] { [] }
    func delete(torrentID: String) async throws {}
}
private final class FakePoller: DownloadPolling, @unchecked Sendable {
    func poll() async throws -> [DownloadStatus] { [] }
}
private final class FakeDeleter: DownloadDeleting, @unchecked Sendable {
    func deleteTorrent(id: String) async throws {}
}

@MainActor
private func downloadStore(req: any DownloadRequesting = FakeReq()) -> DownloadStore {
    DownloadStore(service: req, records: FakeRecords(), poller: FakePoller(), deleter: FakeDeleter())
}

@MainActor
@Suite struct VersionsModelTests {
    private func flow(hit: SearchHit, details: FakeDetails,
                      streams: any StreamSource = FakeStreamSource(),
                      add: Result<TorrentInfo, FakeError> = .failure(.boom)) -> AddFlowStore {
        AddFlowStore(hit: hit, details: details, streamSource: streams, add: FakeAdd(add))
    }

    // MARK: load

    @Test func loadsAndPutsOversizedFirst() async {
        let m = VersionsModel(hit: movieHit(), target: .movie,
                              flow: flow(hit: movieHit(), details: FakeDetails(movie: .success(movieDetails(imdb: "tt1"))),
                                        streams: FakeStreamSource(.success([
                                            cachedStream("small"), oversizedStream("big")]))),
                              downloads: nil, onAdded: {})
        await m.load()
        #expect(m.phase == .ready)
        #expect(m.larger.map(\.infoHash) == ["big"])
        #expect(m.rest.map(\.infoHash) == ["small"])
    }

    @Test func anEpisodeListsThatEpisodesVersions() async {
        let recorder = RecordingStreamSource([cachedStream("ep3")])
        let m = VersionsModel(
            hit: showHit(), target: .episode(season: 1, number: 3),
            flow: flow(hit: showHit(),
                      details: FakeDetails(tv: .success(tvDetails(imdb: "tt9", seasons: 1)),
                                           episodes: [1: .success([episode(3)])]),
                      streams: recorder),
            downloads: nil, onAdded: {})
        await m.load()
        #expect(m.phase == .ready)
        // Season-pack loading always probes `episode: 1` too (the season pack's own query) — what
        // matters is that the EPISODE list itself was queried under the picked episode, not season 1.
        #expect(recorder.kinds.contains(.series(season: 1, episode: 3)))
    }

    @Test func nothingFoundIsEmpty() async {
        let m = VersionsModel(hit: movieHit(), target: .movie,
                              flow: flow(hit: movieHit(), details: FakeDetails(movie: .success(movieDetails(imdb: "tt1")))),
                              downloads: nil, onAdded: {})
        await m.load()
        #expect(m.phase == .empty)
    }

    @Test func anUnresolvableTitleIsFailed() async {
        let m = VersionsModel(hit: movieHit(), target: .movie,
                              flow: flow(hit: movieHit(), details: FakeDetails(movie: .success(movieDetails(imdb: nil)))),
                              downloads: nil, onAdded: {})
        await m.load()
        #expect(m.phase == .failed)
    }

    @Test func signedOutHasNoFlowAndIsFailed() async {
        let m = VersionsModel(hit: movieHit(), target: .movie, flow: nil, downloads: nil, onAdded: {})
        await m.load()
        #expect(m.phase == .failed)
    }

    // MARK: pick

    @Test func anInstantPickPlaysAndRefreshesTheLibrary() async {
        var addedCount = 0
        let stream = cachedStream("a")
        let m = VersionsModel(
            hit: movieHit(), target: .movie,
            flow: flow(hit: movieHit(), details: FakeDetails(movie: .success(movieDetails(imdb: "tt1"))),
                      streams: FakeStreamSource(.success([stream])), add: .success(downloadedInfo())),
            downloads: downloadStore(), onAdded: { addedCount += 1 })
        await m.load()

        let outcome = await m.pick(stream)

        guard case .play = outcome else { Issue.record("expected .play, got \(outcome)"); return }
        #expect(addedCount == 1)
        #expect(m.picking == nil)
    }

    @Test func aNonInstantPickDownloadsExactlyThatVersion() async {
        let stream = cachedStream("b")
        let downloads = downloadStore()
        let m = VersionsModel(
            hit: movieHit(), target: .movie,
            flow: flow(hit: movieHit(), details: FakeDetails(movie: .success(movieDetails(imdb: "tt1"))),
                      streams: FakeStreamSource(.success([stream])), add: .failure(.boom)),
            downloads: downloads, onAdded: {})
        await m.load()

        let outcome = await m.pick(stream)

        #expect(outcome == .downloadStarted)
        let status = downloads.status(forContentKey: DownloadKey.movie(tmdbID: 11))
        #expect(status != nil)
    }

    @Test func anEpisodePickFilesUnderTheEpisodeKey() async {
        let stream = cachedStream("ep")
        let downloads = downloadStore()
        let m = VersionsModel(
            hit: showHit(), target: .episode(season: 1, number: 3),
            flow: flow(hit: showHit(),
                      details: FakeDetails(tv: .success(tvDetails(imdb: "tt9", seasons: 1)),
                                           episodes: [1: .success([episode(3)])]),
                      streams: FakeStreamSource(.success([stream])), add: .failure(.boom)),
            downloads: downloads, onAdded: {})
        await m.load()

        _ = await m.pick(stream)

        let status = downloads.status(forContentKey: DownloadKey.episode(showTmdbID: 22, season: 1, number: 3))
        #expect(status != nil)
        #expect(downloads.status(forContentKey: DownloadKey.movie(tmdbID: 22)) == nil)
    }

    /// Gates the instant-add call so the first `pick` genuinely parks mid-flight, proving the
    /// second call's `guard picking == nil` really observes it busy rather than racing a first
    /// pick that already finished.
    @Test func aSecondPickWhileOneRunsIsIgnored() async {
        let stream = cachedStream("gated")
        let gatedAdd = GatedAdd()
        let f = AddFlowStore(hit: movieHit(), details: FakeDetails(movie: .success(movieDetails(imdb: "tt1"))),
                             streamSource: FakeStreamSource(.success([stream])), add: gatedAdd)
        let m = VersionsModel(hit: movieHit(), target: .movie, flow: f,
                              downloads: downloadStore(), onAdded: {})
        await m.load()

        let first = Task { _ = await m.pick(stream) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(m.picking == stream.infoHash)

        let second = await m.pick(stream)
        #expect(second == .failed(""))

        await gatedAdd.gate.open()
        _ = await first.value
        #expect(m.picking == nil)
    }
}

/// A single-use gate so a test can hold `pick`'s instant-add call open while it checks `picking`.
private actor PickGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

private final class GatedAdd: AddProviding, @unchecked Sendable {
    let gate = PickGate()
    func add(infoHash: String) async throws -> TorrentInfo {
        await gate.wait()
        throw FakeError.boom
    }
}
