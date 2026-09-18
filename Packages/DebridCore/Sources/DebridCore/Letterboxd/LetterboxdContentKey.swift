import Foundation

/// Reads a TMDB id out of a watch key, and refuses everything that is not a film.
///
/// Watch keys come in three shapes: `movie:tmdb:123`, `show:tmdb:1396:s1e2`, and — when TMDB
/// enrichment never matched — the parsed-title fallback `movie:speed:1994`. Only the first can
/// reach Letterboxd, which has no television and no idea what a parsed title is.
public enum LetterboxdContentKey {
    public static func tmdbID(fromMovieKey key: String) -> Int? {
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "movie", parts[1] == "tmdb" else { return nil }
        return Int(parts[2])
    }
}
