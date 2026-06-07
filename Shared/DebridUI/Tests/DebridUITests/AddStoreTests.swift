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
    let perHash: [String: Result<TorrentInfo, FakeError>]
    init(_ result: Result<TorrentInfo, FakeError>, perHash: [String: Result<TorrentInfo, FakeError>] = [:]) {
        self.result = result; self.perHash = perHash
    }
    func add(infoHash: String) async throws -> TorrentInfo { try (perHash[infoHash] ?? result).get() }
}

private func cachedStream(_ hash: String, res: String, langs: [String], size: Int) -> CachedStream {
    CachedStream(infoHash: hash, fileIdx: nil, rawTitle: "t",
                 parsed: ParsedRelease(title: "t", resolution: res),
                 languages: langs, sizeBytes: size, sourceName: nil)
}

@MainActor
@Suite struct AddStoreTests {
    func tv(_ status: String = "downloaded") -> TorrentInfo {
        TorrentInfo(id: "T", filename: "M", hash: "h", bytes: 1, progress: 100, status: status,
                    files: [TorrentFile(id: 1, path: "/M/m.mkv", bytes: 1, selected: 1)],
                    links: ["https://rd/d/X"])
    }

    private func store(streams: Result<[CachedStream], FakeError>,
                       add: Result<TorrentInfo, FakeError> = .failure(.boom)) -> AddStore {
        AddStore(imdbID: "tt1", kind: .movie, originalLanguage: "fr",
                 streamSource: FakeStreamSource(streams), add: FakeAdd(add))
    }

    @Test func loadStreamsPicksOriginalLanguageBest() async {
        let s = store(streams: .success([
            cachedStream("a", res: "2160p", langs: ["en"], size: 100),
            cachedStream("b", res: "1080p", langs: ["fr"], size: 50)]))
        await s.loadStreams()
        #expect(s.state == .streams)
        #expect(s.best?.infoHash == "b")
        #expect(s.isFallback == false)
        #expect(s.ranked.count == 2)
    }

    @Test func loadStreamsFlagsFallbackWhenNoOriginal() async {
        let s = store(streams: .success([cachedStream("a", res: "2160p", langs: ["en"], size: 100)]))
        await s.loadStreams()
        #expect(s.best?.infoHash == "a")
        #expect(s.isFallback == true)
    }

    @Test func noStreamsState() async {
        let s = store(streams: .success([]))
        await s.loadStreams()
        #expect(s.state == .noStreams)
    }

    @Test func streamsFailureState() async {
        let s = store(streams: .failure(.boom))
        await s.loadStreams()
        if case .failed = s.state {} else { Issue.record("expected failed") }
    }

    @Test func addBestSucceeds() async {
        let s = store(streams: .success([cachedStream("b", res: "1080p", langs: ["fr"], size: 50)]),
                      add: .success(tv()))
        await s.loadStreams()
        await s.addBest()
        if case let .added(info) = s.state { #expect(info.id == "T") } else { Issue.record("expected added") }
    }

    @Test func addBestFallsBackToNextWhenTopNotInstant() async {
        // best (b, original-language fr) isn't instant → should fall back to a (success).
        let streams: [CachedStream] = [
            cachedStream("a", res: "2160p", langs: ["en"], size: 100),
            cachedStream("b", res: "1080p", langs: ["fr"], size: 50)]
        let s = AddStore(imdbID: "tt1", kind: .movie, originalLanguage: "fr",
                         streamSource: FakeStreamSource(.success(streams)),
                         add: FakeAdd(.failure(.boom), perHash: ["a": .success(tv())]))
        await s.loadStreams()
        #expect(s.best?.infoHash == "b")
        await s.addBest()
        if case let .added(info) = s.state { #expect(info.id == "T") } else { Issue.record("expected added") }
        #expect(s.best?.infoHash == "a")   // updated to the version that actually landed
    }

    @Test func addFailureSurfacesAddFailed() async {
        let s = store(streams: .success([cachedStream("b", res: "1080p", langs: ["fr"], size: 50)]),
                      add: .failure(.boom))
        await s.loadStreams()
        await s.addBest()
        if case .addFailed = s.state {} else { Issue.record("expected addFailed") }
    }

    // MARK: - Uncached candidates (input to a request-download)

    @Test func uncachedCandidatesAreRankedOriginalLanguageFirst() async {
        let s = store(streams: .success([
            cachedStream("a", res: "2160p", langs: ["en"], size: 100),
            cachedStream("b", res: "1080p", langs: ["fr"], size: 50)]))   // fr = original language
        let candidates = await s.uncachedCandidates()
        #expect(candidates.first?.infoHash == "b")
        #expect(candidates.count == 2)
    }

    @Test func uncachedCandidatesEmptyOnNoResults() async {
        let s = store(streams: .success([]))
        #expect(await s.uncachedCandidates().isEmpty)
    }

    @Test func uncachedCandidatesEmptyOnError() async {
        let s = store(streams: .failure(.boom))
        #expect(await s.uncachedCandidates().isEmpty)
    }

    // MARK: - Show all versions (browse cached + uncached, DMM-style)

    @Test func loadAllVersionsPopulatesRankedList() async {
        let s = store(streams: .success([
            cachedStream("a", res: "2160p", langs: ["en"], size: 100),
            cachedStream("b", res: "1080p", langs: ["fr"], size: 50)]))   // fr = original language
        await s.loadAllVersions()
        #expect(s.allVersions.map(\.infoHash) == ["b", "a"])   // original-language best first
    }

    @Test func loadAllVersionsEmptyOnError() async {
        let s = store(streams: .failure(.boom))
        await s.loadAllVersions()
        #expect(s.allVersions.isEmpty)
    }

    // MARK: - Season-pack mode

    private func seStream(_ hash: String, season: Int, episode: Int?, res: String) -> CachedStream {
        CachedStream(infoHash: hash, fileIdx: nil, rawTitle: "t",
                     parsed: ParsedRelease(title: "t", season: season, episode: episode, resolution: res),
                     languages: ["en"], sizeBytes: 1, sourceName: nil)
    }

    @Test func seasonPackModeRanksOnlyFullSeasonReleases() async {
        // The episode query returns single episodes AND a season pack; pack mode keeps only the pack.
        let streams = [seStream("ep", season: 1, episode: 1, res: "2160p"),
                       seStream("pack", season: 1, episode: nil, res: "1080p")]
        let s = AddStore(imdbID: "tt1", kind: .series(season: 1, episode: 1), originalLanguage: "en",
                         streamSource: FakeStreamSource(.success(streams)),
                         add: FakeAdd(.failure(.boom)), seasonPack: 1)
        await s.loadStreams()
        #expect(s.state == .streams)
        #expect(s.ranked.map(\.infoHash) == ["pack"])
        #expect(s.best?.infoHash == "pack")
    }

    @Test func seasonPackModeNoStreamsWhenNoPack() async {
        let streams = [seStream("ep", season: 1, episode: 1, res: "2160p")]   // only a single episode
        let s = AddStore(imdbID: "tt1", kind: .series(season: 1, episode: 1), originalLanguage: "en",
                         streamSource: FakeStreamSource(.success(streams)),
                         add: FakeAdd(.failure(.boom)), seasonPack: 1)
        await s.loadStreams()
        #expect(s.state == .noStreams)
        #expect(s.best == nil)
    }
}
