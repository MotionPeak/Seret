import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

// MARK: - Fixtures

private func movie(tmdbID: Int? = 70160) -> MediaItem {
    MediaItem(id: "movie:tmdb:\(tmdbID ?? 0)", kind: .movie, title: "The Hunger Games", year: 2012,
              sources: [], seasons: [], tmdbID: tmdbID, posterPath: "/p.jpg")
}
private func show(tmdbID: Int? = 1396) -> MediaItem {
    MediaItem(id: "show:tmdb:\(tmdbID ?? 0)", kind: .show, title: "Breaking Bad", year: 2008,
              sources: [], seasons: [], tmdbID: tmdbID)
}

private func cachedStream(_ hash: String) -> CachedStream {
    CachedStream(infoHash: hash, fileIdx: nil, rawTitle: "Breaking.Bad.S01E03.1080p",
                parsed: ParsedRelease(title: "Breaking Bad", resolution: "1080p"),
                languages: ["en"], sizeBytes: 100, sourceName: nil)
}

/// A season-pack-shaped stream (season set, episode nil) — what `AddStore.seasonPacks(forSeason:)`
/// filters for, unlike the single-episode `cachedStream(_:)` above.
private func seasonPackStream(_ hash: String, season: Int) -> CachedStream {
    CachedStream(infoHash: hash, fileIdx: nil, rawTitle: "Breaking.Bad.S0\(season).1080p",
                parsed: ParsedRelease(title: "Breaking Bad", season: season, resolution: "1080p"),
                languages: ["en"], sizeBytes: 100, sourceName: nil)
}

private func torrentInfo(_ id: String = "T1", status: String = "downloaded", progress: Double = 100)
-> TorrentInfo {
    TorrentInfo(id: id, filename: "Breaking.Bad.S01E03.1080p.mkv", hash: "h", bytes: 1,
                progress: progress, status: status,
                files: [TorrentFile(id: 1, path: "/Breaking.Bad.S01E03.1080p.mkv", bytes: 1, selected: 1)],
                links: ["https://rd/d/X"])
}

// MARK: - Stream/add fakes (mirrors AcquisitionStoreTests, plus a cached/uncached split)

private final class FakeStreamSource: StreamSource {
    let cached: [CachedStream]
    let uncached: [CachedStream]
    init(cached: [CachedStream] = [], uncached: [CachedStream] = []) {
        self.cached = cached; self.uncached = uncached
    }
    func streams(for query: StreamQuery) async throws -> [CachedStream] { cached }
    func streams(for query: StreamQuery, includeUncached: Bool) async throws -> [CachedStream] {
        includeUncached ? uncached : cached
    }
}

private final class FakeAdd: AddProviding, @unchecked Sendable {
    let result: Result<TorrentInfo, FakeError>
    init(_ result: Result<TorrentInfo, FakeError>) { self.result = result }
    func add(infoHash: String) async throws -> TorrentInfo { try result.get() }
}

/// A single-use gate so a test can hold one in-flight `play`/`streams` call open while it checks
/// `finding` for a target that has not resolved yet.
private actor Gate {
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

/// Gates the stream fetch for one specific episode number, so `findingIsTrackedPerTarget` can
/// prove `finding` is keyed per target rather than a single flag.
private final class GatedEpisodeStreamSource: StreamSource, @unchecked Sendable {
    let gate = Gate()
    let gatedEpisode: Int
    let cached: [CachedStream]
    init(gatedEpisode: Int, cached: [CachedStream]) {
        self.gatedEpisode = gatedEpisode; self.cached = cached
    }
    func streams(for query: StreamQuery) async throws -> [CachedStream] {
        if case let .series(_, episode) = query.kind, episode == gatedEpisode {
            await gate.wait()
        }
        return cached
    }
}

// MARK: - Download-store fakes (mirrors DownloadStoreTests)

private final class FakeReq: DownloadRequesting, @unchecked Sendable {
    let result: Result<TorrentInfo, FakeError>
    init(_ result: Result<TorrentInfo, FakeError>) { self.result = result }
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
    private(set) var deleted: [String] = []
    func deleteTorrent(id: String) async throws { deleted.append(id) }
}

@MainActor
private func downloadStore(req: any DownloadRequesting = FakeReq(.success(torrentInfo()))) -> DownloadStore {
    DownloadStore(service: req, records: FakeRecords(), poller: FakePoller(), deleter: FakeDeleter())
}

// MARK: - AddStore factories

/// A movie/episode acquisition engine over one shared cached/uncached stream list.
@MainActor
private func acquisitionFactory(streams: FakeStreamSource,
                                add: Result<TorrentInfo, FakeError>) -> @MainActor (StreamQuery.Kind) -> AddStore? {
    { kind in AddStore(imdbID: "tt1392170", kind: kind, originalLanguage: "en",
                       streamSource: streams, add: FakeAdd(add)) }
}

@MainActor
@Suite struct TitleAcquirerTests {
    private func acquirer(_ item: MediaItem, streams: FakeStreamSource,
                          add: Result<TorrentInfo, FakeError> = .success(torrentInfo()),
                          downloads: DownloadStore? = nil,
                          seasonPack: AddStore? = nil,
                          onAdded: @escaping @MainActor () -> Void = {}) -> TitleAcquirer {
        TitleAcquirer(
            item: item,
            makeAcquisition: { AcquisitionStore(item: item, makeAdd: acquisitionFactory(streams: streams, add: add)) },
            makeSeasonPack: { _ in seasonPack },
            downloads: downloads,
            onAdded: onAdded)
    }

    // MARK: play

    @Test func aFilmWithAnInstantVersionPlaysUnderItsCanonicalKey() async {
        var addedCount = 0
        let a = acquirer(movie(), streams: FakeStreamSource(cached: [cachedStream("a")]),
                         onAdded: { addedCount += 1 })

        let outcome = await a.play(.movie)

        guard case let .play(request) = outcome else {
            Issue.record("expected .play, got \(outcome)"); return
        }
        #expect(request.contentKey == "movie:tmdb:70160")
        #expect(addedCount == 1)
        #expect(a.finding.isEmpty)
    }

    @Test func aFilmWithNothingInstantOffersADownloadAndStartsNone() async {
        let downloads = downloadStore()
        let a = acquirer(movie(), streams: FakeStreamSource(), downloads: downloads)

        let outcome = await a.play(.movie)

        #expect(outcome == .noneInstant)
        #expect(downloads.statuses.isEmpty)
    }

    @Test func anEpisodeWithNothingInstantStartsATrackedDownload() async {
        let downloads = downloadStore()
        let streams = FakeStreamSource(cached: [], uncached: [cachedStream("u")])
        let a = acquirer(show(), streams: streams, downloads: downloads)

        let outcome = await a.play(.episode(season: 1, number: 3))

        #expect(outcome == .downloadStarted)
        let status = downloads.status(forContentKey: "show:tmdb:1396:s1e3")
        #expect(status != nil)
        #expect(status?.tmdbID == 1396)
    }

    @Test func anEpisodeWithNoCandidatesAtAllSaysSo() async {
        let downloads = downloadStore()
        let a = acquirer(show(), streams: FakeStreamSource(), downloads: downloads)

        let outcome = await a.play(.episode(season: 1, number: 3))

        #expect(outcome == .failed("No version of this episode is available to download."))
        #expect(downloads.status(forContentKey: "show:tmdb:1396:s1e3") == nil)
    }

    // MARK: requestDownload

    @Test func requestingAFilmDownloadFilesItUnderTheMovieKey() async {
        let downloads = downloadStore()
        let streams = FakeStreamSource(cached: [], uncached: [cachedStream("u")])
        let a = acquirer(movie(), streams: streams, downloads: downloads)

        let outcome = await a.requestDownload(.movie)

        #expect(outcome == .downloadStarted)
        #expect(downloads.status(forContentKey: "movie:tmdb:70160") != nil)
    }

    @Test func aFilmRequestWithNoCandidatesLetsTheStoreSayWhy() async {
        let downloads = downloadStore()
        let a = acquirer(movie(), streams: FakeStreamSource(), downloads: downloads)

        let outcome = await a.requestDownload(.movie)

        #expect(outcome == .failed("No version available to download."))
    }

    // MARK: finding is per-target

    @Test func findingIsTrackedPerTarget() async {
        let gated = GatedEpisodeStreamSource(gatedEpisode: 3, cached: [])
        let downloads = downloadStore()
        let a = acquirer(show(), streams: FakeStreamSource(), downloads: downloads)
        // Swap in the gated source via a dedicated acquirer so E3's play() parks mid-flight.
        let gatedAcquirer = TitleAcquirer(
            item: show(),
            makeAcquisition: {
                AcquisitionStore(item: show()) { kind in
                    AddStore(imdbID: "tt1", kind: kind, originalLanguage: "en",
                            streamSource: gated, add: FakeAdd(.success(torrentInfo())))
                }
            },
            makeSeasonPack: { _ in nil },
            downloads: downloads,
            onAdded: {})

        let inFlight = Task { _ = await gatedAcquirer.play(.episode(season: 1, number: 3)) }
        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(gatedAcquirer.isBusy(.episode(season: 1, number: 3)))
        #expect(!gatedAcquirer.isBusy(.episode(season: 1, number: 4)))

        let second = await gatedAcquirer.play(.episode(season: 1, number: 3))
        #expect(second == .failed(""))

        await gated.gate.open()
        _ = await inFlight.value
        #expect(!gatedAcquirer.isBusy(.episode(season: 1, number: 3)))
        _ = a   // silence unused-var warning for the unrelated acquirer built above
    }

    // MARK: availability

    @Test func availabilityReadsFindingThenEpisodeThenSeasonThenOwned() async {
        let downloads = downloadStore()
        let s = show(tmdbID: 1396)
        let a = acquirer(s, streams: FakeStreamSource(cached: []), downloads: downloads)

        func row(_ n: Int, downloaded: Bool) -> DetailStore.EpisodeRowInfo {
            let episode = downloaded
                ? Episode(season: 1, number: n,
                          source: MediaSource(torrentID: "t", fileID: 1, restrictedLink: "l",
                                              parsed: ParsedRelease(title: "t")))
                : nil
            return DetailStore.EpisodeRowInfo(season: 1, number: n, meta: nil, ownedEpisode: episode)
        }

        // notDownloaded: nothing anywhere.
        #expect(a.availability(of: row(1, downloaded: false)) == .notDownloaded)

        // downloaded: owned, no active statuses.
        #expect(a.availability(of: row(2, downloaded: true)) == .downloaded)

        // downloading (episode's own tracked download) beats "owned" being false.
        await downloads.applyForTest([DownloadStatus(torrentID: "T3", contentKey: "show:tmdb:1396:s1e3",
                                                      tmdbID: 1396, phase: .downloading, fraction: 0.4)])
        #expect(a.availability(of: row(3, downloaded: false)) == .downloading(0.4))

        // downloading (SEASON download) when the episode itself has no status.
        await downloads.applyForTest([DownloadStatus(torrentID: "T4", contentKey: "show:tmdb:1396:season:1",
                                                      tmdbID: 1396, phase: .downloading, fraction: 0.7)])
        #expect(a.availability(of: row(4, downloaded: false)) == .downloading(0.7))

        // failed episode status.
        await downloads.applyForTest([DownloadStatus(torrentID: "T5", contentKey: "show:tmdb:1396:s1e5",
                                                      tmdbID: 1396, phase: .failed("nope"), fraction: 0)])
        #expect(a.availability(of: row(5, downloaded: false)) == .failed("nope"))

        // finding beats everything, even an owned episode. Gated so the check below cannot race
        // a `play()` that would otherwise complete before `finding` is ever observed.
        let gated = GatedEpisodeStreamSource(gatedEpisode: 6, cached: [])
        let gatedAcquirer = TitleAcquirer(
            item: s,
            makeAcquisition: {
                AcquisitionStore(item: s) { kind in
                    AddStore(imdbID: "tt1", kind: kind, originalLanguage: "en",
                            streamSource: gated, add: FakeAdd(.success(torrentInfo())))
                }
            },
            makeSeasonPack: { _ in nil }, downloads: downloads, onAdded: {})
        let inFlight = Task { _ = await gatedAcquirer.play(.episode(season: 1, number: 6)) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(gatedAcquirer.availability(of: row(6, downloaded: true)) == .finding)
        await gated.gate.open()
        _ = await inFlight.value
    }

    // MARK: season download

    @Test func aSeasonPackIsAddedAndTheLibraryRefreshed() async {
        var addedCount = 0
        let pack = AddStore(imdbID: "tt1", kind: .series(season: 1, episode: 1),
                            originalLanguage: "en",
                            streamSource: FakeStreamSource(cached: [seasonPackStream("pack", season: 1)]),
                            add: FakeAdd(.success(torrentInfo())), seasonPack: 1)
        let a = acquirer(show(), streams: FakeStreamSource(), seasonPack: pack,
                         onAdded: { addedCount += 1 })

        await a.downloadSeason(1)

        #expect(a.seasonPhase(1) == .added)
        #expect(addedCount == 1)
    }

    @Test func noPackFallsBackToATrackedSeasonDownload() async {
        let downloads = downloadStore(req: FakeReq(.success(torrentInfo("T2", status: "downloading",
                                                                        progress: 40))))
        let pack = AddStore(imdbID: "tt1", kind: .series(season: 2, episode: 1),
                            originalLanguage: "en",
                            streamSource: FakeStreamSource(cached: [],
                                                           uncached: [seasonPackStream("u", season: 2)]),
                            add: FakeAdd(.failure(.boom)), seasonPack: 2)
        let a = acquirer(show(), streams: FakeStreamSource(), downloads: downloads, seasonPack: pack)

        await a.downloadSeason(2)

        let status = downloads.status(forContentKey: "show:tmdb:1396:season:2")
        #expect(status != nil)
        if let status { #expect(a.seasonPhase(2) == .downloading(status)) }
    }

    @Test func noPackAndNothingToDownloadIsNoFullSeason() async {
        let downloads = downloadStore()
        let pack = AddStore(imdbID: "tt1", kind: .series(season: 3, episode: 1),
                            originalLanguage: "en", streamSource: FakeStreamSource(),
                            add: FakeAdd(.failure(.boom)), seasonPack: 3)
        let a = acquirer(show(), streams: FakeStreamSource(), downloads: downloads, seasonPack: pack)

        await a.downloadSeason(3)

        #expect(a.seasonPhase(3) == .noFullSeason)
    }

    @Test func signedOutFailsClearly() async {
        let a = acquirer(show(), streams: FakeStreamSource(), seasonPack: nil)

        await a.downloadSeason(1)

        #expect(a.seasonPhase(1) == .failed("Not signed in to Real\u{2011}Debrid."))
    }

    // MARK: cancel

    @Test func cancellingClearsTheStatus() async {
        let downloads = downloadStore()
        let streams = FakeStreamSource(cached: [], uncached: [cachedStream("u")])
        let a = acquirer(movie(), streams: streams, downloads: downloads)

        _ = await a.requestDownload(.movie)
        #expect(downloads.status(forContentKey: "movie:tmdb:70160") != nil)

        await a.cancelDownload(.movie)

        #expect(downloads.status(forContentKey: "movie:tmdb:70160") == nil)
    }
}
