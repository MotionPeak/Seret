import Foundation

public extension MediaItem {
    /// Returns a copy carrying TMDB metadata. When `tmdbID` is non-nil the `id` switches
    /// to a stable TMDB-based key. `sources`, `seasons`, `year` are preserved.
    func withMetadata(tmdbID: Int?, title: String?, posterPath: String?, overview: String?) -> MediaItem {
        MediaItem(
            id: tmdbID.map { "\(kind.rawValue):tmdb:\($0)" } ?? id,
            kind: kind,
            title: title ?? self.title,
            year: year,
            sources: sources,
            seasons: seasons,
            tmdbID: tmdbID,
            posterPath: posterPath,
            backdropPath: backdropPath,
            overview: overview)
    }
}

/// Matches grouped `MediaItem`s to TMDB and fills their metadata. Degrades gracefully:
/// a failed or empty lookup leaves the item as-is (parsed title, no artwork).
public struct MetadataEnricher: Sendable {
    private let tmdb: TMDBClient

    public init(tmdb: TMDBClient) {
        self.tmdb = tmdb
    }

    /// Enriches a single item. Throws only if the TMDB call itself throws (the batch
    /// `enrich(_:)` below catches that per-item).
    public func enrich(_ item: MediaItem) async throws -> MediaItem {
        let results: [TMDBSearchResult]
        switch item.kind {
        case .movie:
            results = try await tmdb.searchMovie(query: item.title, year: item.year)
        case .show:
            results = try await tmdb.searchTV(query: item.title, firstAirYear: item.year)
        }
        guard let match = results.first else { return item }
        return item.withMetadata(tmdbID: match.id, title: match.displayTitle,
                                 posterPath: match.posterPath, overview: match.overview)
    }

    /// Enriches every item concurrently, preserving input order. Per-item lookup failures
    /// are swallowed — that item is returned unenriched rather than failing the whole batch.
    public func enrich(_ items: [MediaItem]) async -> [MediaItem] {
        await withTaskGroup(of: (Int, MediaItem).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    do { return (index, try await self.enrich(item)) }
                    catch { return (index, item) }
                }
            }
            var out = items
            for await (index, enriched) in group { out[index] = enriched }
            return out
        }
    }
}
