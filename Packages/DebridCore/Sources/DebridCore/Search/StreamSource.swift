/// A source of torrents for a title (e.g. the Comet Stremio addon).
public protocol StreamSource: Sendable {
    /// Instantly-cached streams for the query, unranked (caller ranks).
    func streams(for query: StreamQuery) async throws -> [CachedStream]
}

public extension StreamSource {
    /// Candidates for the query. When `includeUncached` is true, sources that support it return
    /// uncached torrents too (for "request download"); the default ignores the flag for
    /// cached-only sources.
    func streams(for query: StreamQuery, includeUncached: Bool) async throws -> [CachedStream] {
        try await streams(for: query)
    }
}
