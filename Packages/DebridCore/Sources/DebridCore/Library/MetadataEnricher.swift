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
            overview: overview,
            addedAt: addedAt)
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
        // TMDB returns most-popular-first, so for a generic title `results.first` can be a wholly
        // different film. Take the first result whose title actually matches the parsed name;
        // if none do, leave the item unenriched rather than stamp the wrong poster/plot on it.
        let matcher = ReleaseMatcher()
        guard let match = results.first(where: { matcher.titleMatches(item.title, $0.displayTitle) })
        else { return item }
        return item.withMetadata(
            tmdbID: match.id,
            title: match.displayTitle.isEmpty ? nil : match.displayTitle,
            posterPath: match.posterPath,
            overview: match.overview)
    }

    /// Enriches every item concurrently, preserving input order. Per-item lookup failures
    /// are swallowed — that item is returned unenriched rather than failing the whole batch.
    public func enrich(_ items: [MediaItem], maxConcurrent: Int = 5) async -> [MediaItem] {
        // Bounded fan-out: at most `maxConcurrent` TMDB searches in flight (an unbounded burst on a
        // cold first load competes with browse + risks TMDB throttling). Order is preserved by index.
        await withTaskGroup(of: (Int, MediaItem).self) { group in
            var next = 0, running = 0
            func add(_ i: Int) {
                let item = items[i]
                group.addTask {
                    do { return (i, try await self.enrich(item)) }
                    catch { return (i, item) }
                }
            }
            while next < items.count && running < maxConcurrent { add(next); next += 1; running += 1 }
            var out = items
            for await (index, enriched) in group {
                out[index] = enriched
                if next < items.count { add(next); next += 1 } else { running -= 1 }
            }
            return out
        }
    }
}
