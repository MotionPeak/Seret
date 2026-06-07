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

private final class FakeAdd: AddProviding {
    let result: Result<TorrentInfo, FakeError>
    init(_ result: Result<TorrentInfo, FakeError>) { self.result = result }
    func add(infoHash: String) async throws -> TorrentInfo { try result.get() }
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

    @Test func addFailureSurfacesAddFailed() async {
        let s = store(streams: .success([cachedStream("b", res: "1080p", langs: ["fr"], size: 50)]),
                      add: .failure(.boom))
        await s.loadStreams()
        await s.addBest()
        if case .addFailed = s.state {} else { Issue.record("expected addFailed") }
    }
}
