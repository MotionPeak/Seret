import Foundation

/// Fans a query out to several `StreamSource`s concurrently and merges their results, deduping by
/// infohash. A source that fails is skipped (degrades, never fails the whole query). When two
/// sources return the same torrent, the cached variant wins so the ⚡/⬇️ badge stays accurate.
///
/// Wiring `AggregateStreamSource([Comet, Torrentio])` gives Comet's accurate instant-cache flags
/// plus Torrentio's broad index (brand-new CAMs), without changing anything downstream.
public struct AggregateStreamSource: StreamSource {
    private let sources: [any StreamSource]
    private let perSourceDeadline: Duration

    /// - Parameter perSourceDeadline: how long any ONE source may take before its results are given
    ///   up on. The merge waits for every source, so without a deadline one provider that never
    ///   answers holds results the other already returned — the viewer watches "Finding cached
    ///   versions" for the length of the URL session's own timeout, a full minute by default, with
    ///   a complete answer sitting in memory the whole time.
    public init(_ sources: [any StreamSource], perSourceDeadline: Duration = .seconds(12)) {
        self.sources = sources
        self.perSourceDeadline = perSourceDeadline
    }

    public func streams(for query: StreamQuery) async throws -> [CachedStream] {
        await merged { try await $0.streams(for: query) }
    }

    public func streams(for query: StreamQuery, includeUncached: Bool) async throws -> [CachedStream] {
        await merged { try await $0.streams(for: query, includeUncached: includeUncached) }
    }

    private func merged(_ fetch: @escaping @Sendable (any StreamSource) async throws -> [CachedStream]) async -> [CachedStream] {
        let sources = self.sources
        let deadline = perSourceDeadline
        return await withTaskGroup(of: [CachedStream].self) { group in
            for source in sources {
                group.addTask {
                    await Self.withDeadline(deadline) { (try? await fetch(source)) ?? [] }
                }
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

    /// Whichever finishes first: the work, or the clock. A timed-out source contributes nothing
    /// rather than blocking the merge, which is the same degradation a failing source already got.
    private static func withDeadline(
        _ deadline: Duration,
        _ work: @escaping @Sendable () async -> [CachedStream]
    ) async -> [CachedStream] {
        await withTaskGroup(of: [CachedStream]?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: deadline)
                return nil
            }
            let winner = await group.next() ?? nil
            group.cancelAll()
            return winner ?? []
        }
    }
}
