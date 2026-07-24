import Foundation

/// Maps Seret domain models (TMDB-keyed) to Trakt identity refs, and converts between the
/// watch-progress content keys (as built by `MetadataEnricher` + `WatchKey`) and Trakt refs.
///
/// Content-key scheme (must stay in lockstep with `MetadataEnricher.id` and `WatchKey`):
///   movie:   `movie:tmdb:{tmdbID}`
///   episode: `show:tmdb:{tmdbID}:s{season}e{number}`
public enum TraktMapping {
    public static func ref(forMovie item: MediaItem) -> TraktMediaRef? {
        item.tmdbID.map { .movie(tmdb: $0) }
    }

    public static func ref(forShow show: MediaItem, episode: Episode) -> TraktMediaRef? {
        show.tmdbID.map { .episode(showTmdb: $0, season: episode.season, number: episode.number) }
    }

    /// The series as a whole (for a show-level rating), not a specific episode.
    public static func ref(forShow show: MediaItem) -> TraktMediaRef? {
        show.tmdbID.map { .show(tmdb: $0) }
    }

    public static func movieContentKey(tmdb: Int) -> String { "movie:tmdb:\(tmdb)" }

    public static func showContentKey(tmdb: Int) -> String { "show:tmdb:\(tmdb)" }

    public static func episodeContentKey(showTmdb: Int, season: Int, number: Int) -> String {
        "show:tmdb:\(showTmdb):s\(season)e\(number)"
    }

    /// Content key for a Trakt ref (the key Home/Detail/Library look up).
    public static func contentKey(for ref: TraktMediaRef) -> String {
        switch ref {
        case let .movie(tmdb): return movieContentKey(tmdb: tmdb)
        case let .show(tmdb): return showContentKey(tmdb: tmdb)
        case let .episode(showTmdb, season, number):
            return episodeContentKey(showTmdb: showTmdb, season: season, number: number)
        }
    }

    /// Parse a content key back to a Trakt ref. Returns nil for non-TMDB (unenriched) keys.
    public static func ref(forContentKey key: String) -> TraktMediaRef? {
        let parts = key.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 3, parts[0] == "movie", parts[1] == "tmdb", let id = Int(parts[2]) {
            return .movie(tmdb: id)
        }
        // A 3-part show key is the series itself ("show:tmdb:1399"); 4 parts adds the episode.
        if parts.count == 3, parts[0] == "show", parts[1] == "tmdb", let id = Int(parts[2]) {
            return .show(tmdb: id)
        }
        if parts.count == 4, parts[0] == "show", parts[1] == "tmdb", let id = Int(parts[2]),
           let se = parseSeasonEpisode(parts[3]) {
            return .episode(showTmdb: id, season: se.season, number: se.number)
        }
        return nil
    }

    static func parseSeasonEpisode(_ s: String) -> (season: Int, number: Int)? {
        guard s.first == "s", let eIdx = s.firstIndex(of: "e") else { return nil }
        guard let season = Int(s[s.index(after: s.startIndex)..<eIdx]),
              let number = Int(s[s.index(after: eIdx)...]) else { return nil }
        return (season, number)
    }
}
