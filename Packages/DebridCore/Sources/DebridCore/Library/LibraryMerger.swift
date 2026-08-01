import Foundation

/// Collapses library entries that turned out to be the SAME title into one.
///
/// Grouping keys a movie by its parsed filename (`movie:theodyssey:2026`), but TMDB enrichment
/// re-keys it by TMDB id afterwards — so two RD torrents whose names parse differently
/// ("The.Odyssey.2026.1080p.TELESYNC.x264" vs "...HEVC", or one with no year at all) stay separate
/// through grouping and only collide once enriched. Left unmerged they are two `MediaItem`s
/// sharing one `id`, which SwiftUI's `ForEach` renders as a single card plus blank gaps, and each
/// one's Detail page lists only ONE of the versions actually owned.
///
/// Pure and order-preserving: the first occurrence keeps its position, later duplicates fold into
/// it. Merging is by `id` alone, so items that never enriched (still keyed by parsed title) are
/// only merged when they genuinely parsed identically.
public struct LibraryMerger: Sendable {
    public init() {}

    public func merge(_ items: [MediaItem]) -> [MediaItem] {
        var order: [String] = []
        var byID: [String: MediaItem] = [:]
        for item in items {
            if let existing = byID[item.id] {
                byID[item.id] = Self.combine(existing, item)
            } else {
                order.append(item.id)
                byID[item.id] = item
            }
        }
        return order.compactMap { byID[$0] }
    }

    /// Folds `later` into `first`. Metadata prefers whichever copy actually has it (one duplicate
    /// may have failed its TMDB lookup), and `addedAt` takes the newest so a freshly-added version
    /// resurfaces the title in Recently Added.
    static func combine(_ first: MediaItem, _ later: MediaItem) -> MediaItem {
        MediaItem(id: first.id,
                  kind: first.kind,
                  title: first.title,
                  year: first.year ?? later.year,
                  sources: mergeSources(first.sources, later.sources),
                  seasons: mergeSeasons(first.seasons, later.seasons),
                  tmdbID: first.tmdbID ?? later.tmdbID,
                  posterPath: first.posterPath ?? later.posterPath,
                  backdropPath: first.backdropPath ?? later.backdropPath,
                  overview: first.overview ?? later.overview,
                  addedAt: newest(first.addedAt, later.addedAt))
    }

    /// Appends `later`'s versions, dropping any that point at the same RD file (the same torrent
    /// can back both copies when one was built from a stale snapshot).
    static func mergeSources(_ first: [MediaSource], _ later: [MediaSource]) -> [MediaSource] {
        var seen = Set(first.map(sourceKey))
        var out = first
        for source in later where seen.insert(sourceKey(source)).inserted {
            out.append(source)
        }
        return out
    }

    /// Unions two season lists. Episodes are deduped by season+number keeping the first-seen
    /// source — the same rule `LibraryBuilder` applies within one show.
    static func mergeSeasons(_ first: [Season], _ later: [Season]) -> [Season] {
        guard !later.isEmpty else { return first }
        guard !first.isEmpty else { return later }
        var episodes: [String: Episode] = [:]
        for season in first + later {
            for episode in season.episodes where episodes[episode.id] == nil {
                episodes[episode.id] = episode
            }
        }
        let bySeason = Dictionary(grouping: episodes.values, by: { $0.season })
        return bySeason.keys.sorted().map { number in
            Season(number: number, episodes: bySeason[number]!.sorted { $0.number < $1.number })
        }
    }

    private static func sourceKey(_ source: MediaSource) -> String {
        "\(source.torrentID)#\(source.fileID.map(String.init) ?? "-")"
    }

    private static func newest(_ a: Date?, _ b: Date?) -> Date? {
        guard let a else { return b }
        guard let b else { return a }
        return max(a, b)
    }
}
