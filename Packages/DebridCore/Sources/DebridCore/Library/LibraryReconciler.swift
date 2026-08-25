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

    /// Every RD torrent id an item draws from: a movie's sources, plus every VERSION of every
    /// episode — the primary and its alternates alike, since each alternate is its own torrent.
    static func torrentIDs(of item: MediaItem) -> Set<String> {
        var ids = Set(item.sources.map(\.torrentID))
        for season in item.seasons {
            for episode in season.episodes {
                for source in episode.sources { ids.insert(source.torrentID) }
            }
        }
        return ids
    }

    /// How `LibraryBuilder` groups an item: a show by title alone, a movie by title AND year.
    /// Mirrors the ids it builds, so matching on this is matching on the same rule — including the
    /// year for movies, which keeps two same-titled films of different years apart.
    static func groupingKey(of item: MediaItem) -> String {
        switch item.kind {
        case .movie:
            return "movie:\(LibraryBuilder.titleKey(item.title))\(item.year.map { ":\($0)" } ?? "")"
        case .show:
            return "show:\(LibraryBuilder.titleKey(item.title))"
        }
    }

    /// True when RD's current torrent-id set differs from what `cached` was built from.
    public func hasDelta(cached: [MediaItem], rdTorrentIDs: Set<String>) -> Bool {
        let cachedIDs = cached.reduce(into: Set<String>()) { $0.formUnion(Self.torrentIDs(of: $1)) }
        return cachedIDs != rdTorrentIDs
    }

    /// True when RD's current torrent-id set differs from the set seen at the last refresh. Exact —
    /// non-item-producing torrents (non-video, empty) are included in `seenTorrentIDs`, so an
    /// unchanged library takes the cheap path (no `/torrents/info` fan-out every launch).
    public func hasDelta(seenTorrentIDs: Set<String>, rdTorrentIDs: Set<String>) -> Bool {
        seenTorrentIDs != rdTorrentIDs
    }

    /// How a torrent is identified for change detection: its id *and* its status. A torrent keeps
    /// its id for its whole life, so an id-only comparison cannot see the one change that turns a
    /// pending download into a playable title.
    public static func state(of torrent: Torrent) -> String { "\(torrent.id):\(torrent.status)" }

    /// Every torrent's `id:status`, as a set.
    public static func states(of torrents: [Torrent]) -> Set<String> {
        Set(torrents.map(state(of:)))
    }

    /// True when RD's torrents differ — in membership *or* in status — from what the last refresh
    /// recorded. A `nil` `seen` means the snapshot predates status tracking, which must refresh
    /// once so the states get written.
    public func hasDelta(seenTorrentStates seen: Set<String>?, rdTorrentStates: Set<String>) -> Bool {
        guard let seen else { return true }
        return seen != rdTorrentStates
    }

    /// Splits the freshly-grouped library into carried-over (reuse cached TMDB metadata) and
    /// new (enrich) — preserving fresh order so the caller can reassemble after enriching.
    public func reconcile(fresh: [MediaItem], cached: [MediaItem]) -> [Reconciled] {
        var byTorrent: [String: MediaItem] = [:]
        var byGrouping: [String: MediaItem] = [:]
        for item in cached {
            for id in Self.torrentIDs(of: item) { byTorrent[id] = item }
            if item.tmdbID != nil, byGrouping[Self.groupingKey(of: item)] == nil {
                byGrouping[Self.groupingKey(of: item)] = item
            }
        }
        return fresh.map { item in
            // Torrent id first — the strongest identity there is. Then the grouping key, which is
            // what `LibraryBuilder` itself groups by.
            //
            // That second lookup restores something the incremental refresh took away. When the
            // whole account was re-grouped, a newly-added episode torrent landed in the SAME
            // accumulator as the show's existing ones and was matched here through one of those,
            // so TMDB was never asked about a show already known. Grouping only the changed
            // torrents means a new one arrives alone, sharing no id — and a show's filename year is
            // the SEASON's, which TMDB filters on hard, so the lookup returns nothing and the
            // fragment can never merge into the show it belongs to. Two cards, one posterless,
            // holding the episode the viewer just added.
            let match = Self.torrentIDs(of: item).lazy.compactMap { byTorrent[$0] }.first
                ?? byGrouping[Self.groupingKey(of: item)]
            if let match, match.tmdbID != nil {
                return .carried(item.withMetadata(tmdbID: match.tmdbID, title: match.title,
                                                  posterPath: match.posterPath, overview: match.overview))
            }
            return .needsEnrichment(item)
        }
    }
}
