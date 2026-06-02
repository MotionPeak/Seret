import Foundation

/// The outcome of reconciling one freshly-grouped item against the cache, in fresh-library order.
public enum Reconciled: Sendable, Equatable {
    case carried(MediaItem)         // content already known + enriched → cached metadata reused
    case needsEnrichment(MediaItem) // genuinely new (or never enriched) → must hit TMDB
}

/// Pure incremental-refresh logic. Identity is by **shared RD torrent id** (stable), so an item
/// already in the cache carries its TMDB metadata over onto the fresh structure (picking up any
/// new episodes), while genuinely-new items are flagged for enrichment. No I/O.
public struct LibraryReconciler: Sendable {
    public init() {}

    /// Every RD torrent id an item draws from (movie sources + every episode's source).
    static func torrentIDs(of item: MediaItem) -> Set<String> {
        var ids = Set(item.sources.map(\.torrentID))
        for season in item.seasons {
            for episode in season.episodes { ids.insert(episode.source.torrentID) }
        }
        return ids
    }

    /// True when RD's current torrent-id set differs from what `cached` was built from.
    public func hasDelta(cached: [MediaItem], rdTorrentIDs: Set<String>) -> Bool {
        let cachedIDs = cached.reduce(into: Set<String>()) { $0.formUnion(Self.torrentIDs(of: $1)) }
        return cachedIDs != rdTorrentIDs
    }

    /// Splits the freshly-grouped library into carried-over (reuse cached TMDB metadata) and
    /// new (enrich) — preserving fresh order so the caller can reassemble after enriching.
    public func reconcile(fresh: [MediaItem], cached: [MediaItem]) -> [Reconciled] {
        var byTorrent: [String: MediaItem] = [:]
        for item in cached {
            for id in Self.torrentIDs(of: item) { byTorrent[id] = item }
        }
        return fresh.map { item in
            let match = Self.torrentIDs(of: item).lazy.compactMap { byTorrent[$0] }.first
            if let match, match.tmdbID != nil {
                return .carried(item.withMetadata(tmdbID: match.tmdbID, title: match.title,
                                                  posterPath: match.posterPath, overview: match.overview))
            }
            return .needsEnrichment(item)
        }
    }
}
