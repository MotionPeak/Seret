/// A source of torrents for a title (e.g. the Comet Stremio addon).
public protocol StreamSource: Sendable {
    /// Instantly-cached streams for the query, unranked (caller ranks).
    func streams(for query: StreamQuery) async throws -> [CachedStream]

    /// Candidates for the query. When `includeUncached` is true, sources that support it return
    /// uncached torrents too (for "request download"). Declared in the protocol (not just the
    /// extension) so a conformer's override is dispatched through an `any StreamSource` existential.
    func streams(for query: StreamQuery, includeUncached: Bool) async throws -> [CachedStream]
}

public extension StreamSource {
    /// Default for cached-only sources: ignore the flag.
    func streams(for query: StreamQuery, includeUncached: Bool) async throws -> [CachedStream] {
        try await streams(for: query)
    }
}
