/// A source of already-cached torrents for a title (e.g. the Comet Stremio addon).
public protocol StreamSource: Sendable {
    /// Returns instantly-cached streams for the query, unranked (caller ranks).
    func streams(for query: StreamQuery) async throws -> [CachedStream]
}
