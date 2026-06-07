import Foundation

/// Fans a query out to several `StreamSource`s concurrently and merges their results, deduping by
/// infohash. A source that fails is skipped (degrades, never fails the whole query). When two
/// sources return the same torrent, the cached variant wins so the ⚡/⬇️ badge stays accurate.
///
/// Wiring `AggregateStreamSource([Comet, Torrentio])` gives Comet's accurate instant-cache flags
/// plus Torrentio's broad index (brand-new CAMs), without changing anything downstream.
public struct AggregateStreamSource: StreamSource {
    private let sources: [any StreamSource]

    public init(_ sources: [any StreamSource]) { self.sources = sources }

    public func streams(for query: StreamQuery) async throws -> [CachedStream] {
        await merged { try await $0.streams(for: query) }
    }

    public func streams(for query: StreamQuery, includeUncached: Bool) async throws -> [CachedStream] {
        await merged { try await $0.streams(for: query, includeUncached: includeUncached) }
    }

    private func merged(_ fetch: @escaping @Sendable (any StreamSource) async throws -> [CachedStream]) async -> [CachedStream] {
        let sources = self.sources
        return await withTaskGroup(of: [CachedStream].self) { group in
            for source in sources {
                group.addTask { (try? await fetch(source)) ?? [] }
            }
            var byHash: [String: CachedStream] = [:]
            for await streams in group {
                for stream in streams {
                    if let existing = byHash[stream.infoHash] {
                        if !existing.isCached && stream.isCached { byHash[stream.infoHash] = stream }
                    } else {
                        byHash[stream.infoHash] = stream
                    }
                }
            }
            return Array(byHash.values)
        }
    }
}
