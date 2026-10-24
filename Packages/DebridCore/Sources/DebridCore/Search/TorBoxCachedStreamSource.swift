import Foundation

/// Answers "which of these info-hashes does the provider already have cached?".
public protocol CachedHashChecking: Sendable {
    /// The subset of `hashes` that is instantly available, lowercased.
    func checkCached(hashes: [String]) async throws -> Set<String>
}

extension TorBoxClient: CachedHashChecking {}

/// Wraps an indexer (`TorrentioStreamSource`, …) and stamps each result with whether TorBox has it
/// cached. Indexers report an RD cache flag at best, so the wrapper always asks the base for the
/// full list and decides the badge itself.
///
/// A failing cache check degrades to "nothing is known to be cached" rather than failing the
/// search: the viewer still gets the list, minus the instant badges.
public struct TorBoxCachedStreamSource: StreamSource {
    /// Label shown on a result TorBox can serve instantly.
    static let sourceLabel = "TB"

    private let base: any StreamSource
    private let checker: any CachedHashChecking

    public init(base: any StreamSource, checker: any CachedHashChecking) {
        self.base = base
        self.checker = checker
    }

    public func streams(for query: StreamQuery) async throws -> [CachedStream] {
        try await streams(for: query, includeUncached: false)
    }

    public func streams(for query: StreamQuery, includeUncached: Bool) async throws -> [CachedStream] {
        let candidates = try await base.streams(for: query, includeUncached: true)
        guard !candidates.isEmpty else { return [] }

        var seen = Set<String>()
        let hashes = candidates.map { $0.infoHash.lowercased() }.filter { seen.insert($0).inserted }
        let cached = (try? await checker.checkCached(hashes: hashes)) ?? []

        let marked = candidates.map { stream -> CachedStream in
            let hit = cached.contains(stream.infoHash.lowercased())
            return CachedStream(
                infoHash: stream.infoHash, fileIdx: stream.fileIdx, rawTitle: stream.rawTitle,
                parsed: stream.parsed, languages: stream.languages, sizeBytes: stream.sizeBytes,
                sourceName: hit ? Self.sourceLabel : stream.sourceName, isCached: hit,
                subtitleLanguages: stream.subtitleLanguages, isTheatreCopy: stream.isTheatreCopy)
        }
        return includeUncached ? marked : marked.filter(\.isCached)
    }
}
