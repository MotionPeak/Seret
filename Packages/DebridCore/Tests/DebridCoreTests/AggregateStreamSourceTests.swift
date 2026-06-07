import Testing
import Foundation
@testable import DebridCore

private enum FakeError: Error { case boom }

private func stream(_ hash: String, cached: Bool) -> CachedStream {
    CachedStream(infoHash: hash, fileIdx: nil, rawTitle: "t", parsed: ParsedRelease(title: "t"),
                 languages: [], sizeBytes: nil, sourceName: nil, isCached: cached)
}

private struct FakeSource: StreamSource {
    var cached: [CachedStream] = []
    var uncached: [CachedStream] = []
    var fail = false
    func streams(for query: StreamQuery) async throws -> [CachedStream] {
        if fail { throw FakeError.boom }; return cached
    }
    func streams(for query: StreamQuery, includeUncached: Bool) async throws -> [CachedStream] {
        if fail { throw FakeError.boom }; return includeUncached ? uncached : cached
    }
}

@Suite struct AggregateStreamSourceTests {
    private func q() -> StreamQuery { StreamQuery(imdbID: "tt1", kind: .movie, originalLanguage: "en") }

    @Test func mergesUncachedFromAllSources() async throws {
        let a = FakeSource(uncached: [stream("a", cached: false)])
        let b = FakeSource(uncached: [stream("b", cached: false)])
        let agg = AggregateStreamSource([a, b])
        let merged = try await agg.streams(for: q(), includeUncached: true)
        #expect(Set(merged.map(\.infoHash)) == ["a", "b"])
    }

    @Test func dedupesSharedInfoHashPreferringCached() async throws {
        let a = FakeSource(uncached: [stream("x", cached: false)])   // Torrentio: uncached
        let b = FakeSource(uncached: [stream("x", cached: true)])    // Comet: knows it's cached
        let agg = AggregateStreamSource([a, b])
        let merged = try await agg.streams(for: q(), includeUncached: true)
        #expect(merged.count == 1)
        #expect(merged.first?.isCached == true)   // the cached variant wins (accurate badge)
    }

    @Test func degradesWhenOneSourceFails() async throws {
        let ok = FakeSource(uncached: [stream("ok", cached: false)])
        let bad = FakeSource(fail: true)
        let agg = AggregateStreamSource([ok, bad])
        let merged = try await agg.streams(for: q(), includeUncached: true)
        #expect(merged.map(\.infoHash) == ["ok"])   // bad source ignored, not fatal
    }

    @Test func cachedOnlyPathQueriesChildrenCachedOnly() async throws {
        let comet = FakeSource(cached: [stream("c", cached: true)], uncached: [stream("u", cached: false)])
        let torrentio = FakeSource(cached: [], uncached: [stream("t", cached: false)])
        let agg = AggregateStreamSource([comet, torrentio])
        let cachedOnly = try await agg.streams(for: q())
        #expect(cachedOnly.map(\.infoHash) == ["c"])   // only the instant one, Torrentio stays out
    }
}
