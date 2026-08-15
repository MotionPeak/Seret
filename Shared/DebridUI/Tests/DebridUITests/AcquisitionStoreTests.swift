import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

private final class FakeStreamSource: StreamSource {
    let result: Result<[CachedStream], FakeError>
    init(_ result: Result<[CachedStream], FakeError>) { self.result = result }
    func streams(for query: StreamQuery) async throws -> [CachedStream] { try result.get() }
}

private final class FakeAdd: AddProviding, @unchecked Sendable {
    let result: Result<TorrentInfo, FakeError>
    init(_ result: Result<TorrentInfo, FakeError>) { self.result = result }
    func add(infoHash: String) async throws -> TorrentInfo { try result.get() }
}

private func cachedStream(_ hash: String) -> CachedStream {
    CachedStream(infoHash: hash, fileIdx: nil, rawTitle: "The Hunger Games 2012 1080p",
                 parsed: ParsedRelease(title: "The Hunger Games", resolution: "1080p"),
                 languages: ["en"], sizeBytes: 100, sourceName: nil)
}

private func torrentInfo() -> TorrentInfo {
    TorrentInfo(id: "T1", filename: "The.Hunger.Games.2012.1080p.mkv", hash: "h", bytes: 1,
                progress: 100, status: "downloaded",
                files: [TorrentFile(id: 1, path: "/The.Hunger.Games.2012.1080p.mkv",
                                    bytes: 1, selected: 1)],
                links: ["https://rd/d/X"])
}

@MainActor
@Suite struct AcquisitionStoreTests {
    private func movie() -> MediaItem {
        MediaItem(id: "movie:tmdb:70160", kind: .movie, title: "The Hunger Games", year: 2012,
                  sources: [], seasons: [], tmdbID: 70160, posterPath: "/p.jpg")
    }
    private func show() -> MediaItem {
        MediaItem(id: "show:tmdb:1399", kind: .show, title: "Game of Thrones", year: 2011,
                  sources: [], seasons: [], tmdbID: 1399)
    }

    private func store(_ item: MediaItem,
                       streams: Result<[CachedStream], FakeError>,
                       add: Result<TorrentInfo, FakeError>) -> AcquisitionStore {
        AcquisitionStore(item: item) { kind in
            AddStore(imdbID: "tt1392170", kind: kind, originalLanguage: "en",
                     streamSource: FakeStreamSource(streams), add: FakeAdd(add))
        }
    }

    @Test func playBestProducesAPlayableRequestForAMovie() async {
        let s = store(movie(), streams: .success([cachedStream("a")]), add: .success(torrentInfo()))
        await s.playBest(.movie)
        guard case let .ready(request) = s.phase else {
            Issue.record("expected .ready, got \(s.phase)"); return
        }
        #expect(request.contentKey == "movie:tmdb:70160")
        #expect(request.label == "The Hunger Games")
        #expect(request.source.torrentID == "T1")
        #expect(request.episode == nil)
        #expect(request.fromStart == true)
    }

    @Test func playBestKeysAnEpisodeLikeTheLibraryDoes() async {
        let s = store(show(), streams: .success([cachedStream("a")]), add: .success(torrentInfo()))
        await s.playBest(.episode(season: 4, number: 9))
        guard case let .ready(request) = s.phase else {
            Issue.record("expected .ready, got \(s.phase)"); return
        }
        #expect(request.contentKey == "show:tmdb:1399:s4e9")
        #expect(request.contentKey == DownloadKey.episode(showTmdbID: 1399, season: 4, number: 9))
        #expect(request.label == "Game of Thrones — S4·E9")
        #expect(request.episode?.season == 4)
        #expect(request.episode?.number == 9)
    }

    @Test func nothingCachedIsNotAFailure() async {
        let s = store(movie(), streams: .success([]), add: .success(torrentInfo()))
        await s.playBest(.movie)
        #expect(s.phase == .noneCached)
    }

    @Test func aStreamSourceErrorFails() async {
        let s = store(movie(), streams: .failure(.boom), add: .success(torrentInfo()))
        await s.playBest(.movie)
        guard case .failed = s.phase else { Issue.record("expected .failed, got \(s.phase)"); return }
    }

    @Test func anAddThatNeverLandsFails() async {
        let s = store(movie(), streams: .success([cachedStream("a")]), add: .failure(.boom))
        await s.playBest(.movie)
        guard case .failed = s.phase else { Issue.record("expected .failed, got \(s.phase)"); return }
    }

    @Test func noAddStoreMeansFailedNotSilence() async {
        let s = AcquisitionStore(item: movie()) { _ in nil }
        await s.playBest(.movie)
        guard case .failed = s.phase else { Issue.record("expected .failed, got \(s.phase)"); return }
    }

    @Test func resetReturnsToIdle() async {
        let s = store(movie(), streams: .success([cachedStream("a")]), add: .success(torrentInfo()))
        await s.playBest(.movie)
        s.reset()
        #expect(s.phase == .idle)
    }
}
