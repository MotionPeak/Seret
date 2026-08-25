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
        guard let match = try await match(for: item) else { return item }
        return Self.applying(match, to: item)
    }

    /// The TMDB result this item should take its metadata from, or nil when nothing matches.
    private func match(for item: MediaItem) async throws -> TMDBSearchResult? {
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
        return results.first { matcher.titleMatches(item.title, $0.displayTitle) }
    }

    private static func applying(_ match: TMDBSearchResult, to item: MediaItem) -> MediaItem {
        item.withMetadata(
            tmdbID: match.id,
            title: match.displayTitle.isEmpty ? nil : match.displayTitle,
            posterPath: match.posterPath,
            overview: match.overview)
    }

    /// What identifies one TMDB question. Items sharing it will merge into a single title once
    /// enriched, so they only need asking about once.
    private struct Query: Hashable {
        let kind: MediaKind
        let title: String
        let year: Int?
    }

    /// Enriches every item concurrently, preserving input order. Per-item lookup failures
    /// are swallowed — that item is returned unenriched rather than failing the whole batch.
    public func enrich(_ items: [MediaItem], maxConcurrent: Int = 5) async -> [MediaItem] {
        // Items that will merge into one title once enriched ask TMDB the SAME question. A film
        // held in three qualities is three separate items here, and it used to be three identical
        // searches — on a cold load, where every title is new at once and the fan-out is already
        // the slowest thing the app does. Ask once per distinct question and apply the answer to
        // each of them.
        var indicesByQuery: [Query: [Int]] = [:]
        for (i, item) in items.enumerated() {
            indicesByQuery[Query(kind: item.kind, title: item.title, year: item.year),
                           default: []].append(i)
        }
        // Sorted by first position so the request ORDER is stable too, not just the output.
        let groups = indicesByQuery.values.sorted { ($0.first ?? 0) < ($1.first ?? 0) }

        // Bounded fan-out: at most `maxConcurrent` TMDB searches in flight (an unbounded burst on a
        // cold first load competes with browse + risks TMDB throttling). Order is preserved by index.
        return await withTaskGroup(of: (Int, TMDBSearchResult?).self) { group in
            var next = 0, running = 0
            func add(_ g: Int) {
                let representative = items[groups[g][0]]
                group.addTask {
                    do { return (g, try await self.match(for: representative)) }
                    catch { return (g, nil) }
                }
            }
            while next < groups.count && running < maxConcurrent { add(next); next += 1; running += 1 }
            var out = items
            for await (g, match) in group {
                if let match {
                    for index in groups[g] { out[index] = Self.applying(match, to: items[index]) }
                }
                if next < groups.count { add(next); next += 1 } else { running -= 1 }
            }
            return out
        }
    }
}
