import Testing
import Foundation
@testable import DebridCore

private enum FakeError: Error { case boom }

private func stream(_ hash: String, source: String? = "Torrentio", cached: Bool = false) -> CachedStream {
    CachedStream(infoHash: hash, fileIdx: 3, rawTitle: "Movie.2020.1080p", parsed: ParsedRelease(title: "Movie"),
                 languages: ["en"], sizeBytes: 123, sourceName: source, isCached: cached,
                 subtitleLanguages: ["he"], isTheatreCopy: true)
}

/// Records which flag the wrapper asked the base for.
private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var flags: [Bool] = []
    func record(_ flag: Bool) { lock.lock(); flags.append(flag); lock.unlock() }
    var all: [Bool] { lock.lock(); defer { lock.unlock() }; return flags }
}

private struct FakeBase: StreamSource {
    let results: [CachedStream]
    let calls: Calls
    func streams(for query: StreamQuery) async throws -> [CachedStream] {
        calls.record(false); return results.filter(\.isCached)
    }
    func streams(for query: StreamQuery, includeUncached: Bool) async throws -> [CachedStream] {
        calls.record(includeUncached); return includeUncached ? results : results.filter(\.isCached)
    }
}

private struct FakeChecker: CachedHashChecking {
    var cached: Set<String> = []
    var fail = false
    func checkCached(hashes: [String]) async throws -> Set<String> {
        if fail { throw FakeError.boom }
        return cached
    }
}

@Suite struct TorBoxCachedStreamSourceTests {
    private func q() -> StreamQuery { StreamQuery(imdbID: "tt1", kind: .movie, originalLanguage: "en") }

    @Test func marksCheckedHashesCached() async throws {
        let calls = Calls()
        let base = FakeBase(results: [stream("aaa"), stream("bbb")], calls: calls)
        let source = TorBoxCachedStreamSource(base: base, checker: FakeChecker(cached: ["aaa"]))
        let out = try await source.streams(for: q(), includeUncached: true)
        let a = try #require(out.first { $0.infoHash == "aaa" })
        let b = try #require(out.first { $0.infoHash == "bbb" })
        #expect(a.isCached && a.sourceName == "TB")
        #expect(!b.isCached && b.sourceName == "Torrentio")
        // Every other field survives the rebuild.
        #expect(a.fileIdx == 3 && a.rawTitle == "Movie.2020.1080p" && a.languages == ["en"])
        #expect(a.sizeBytes == 123 && a.subtitleLanguages == ["he"] && a.isTheatreCopy)
        #expect(calls.all == [true])
    }

    @Test func cachedOnlyFiltersUncached() async throws {
        let calls = Calls()
        let base = FakeBase(results: [stream("aaa"), stream("bbb")], calls: calls)
        let source = TorBoxCachedStreamSource(base: base, checker: FakeChecker(cached: ["aaa"]))
        let out = try await source.streams(for: q())
        #expect(out.map(\.infoHash) == ["aaa"])
        let out2 = try await source.streams(for: q(), includeUncached: false)
        #expect(out2.map(\.infoHash) == ["aaa"])
        #expect(calls.all == [true, true])   // always asks the base for everything
    }

    @Test func checkFailureDegradesToUncached() async throws {
        let calls = Calls()
        let base = FakeBase(results: [stream("aaa", cached: false)], calls: calls)
        let source = TorBoxCachedStreamSource(base: base, checker: FakeChecker(fail: true))
        let all = try await source.streams(for: q(), includeUncached: true)
        #expect(all.map(\.infoHash) == ["aaa"])
        #expect(all.allSatisfy { !$0.isCached })
        let cachedOnly = try await source.streams(for: q(), includeUncached: false)
        #expect(cachedOnly.isEmpty)
    }

    @Test func hashMatchIsCaseInsensitive() async throws {
        let calls = Calls()
        let base = FakeBase(results: [stream("ABCDEF")], calls: calls)
        let source = TorBoxCachedStreamSource(base: base, checker: FakeChecker(cached: ["abcdef"]))
        let out = try await source.streams(for: q(), includeUncached: true)
        #expect(out.first?.isCached == true)
        #expect(out.first?.infoHash == "ABCDEF")   // the hash itself is untouched
    }
}
