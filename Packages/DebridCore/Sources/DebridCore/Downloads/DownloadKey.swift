import Foundation

/// Stable keys identifying what a download is *for*.
///
/// Movies and episodes reuse `WatchKey`'s content-key forms verbatim, so a Detail screen can look
/// up a download with the same key it uses for watch state.
///
/// Season packs get a download-only form. It is deliberately `season:{n}` rather than `s{n}`:
/// `TraktMapping.ref(forContentKey:)` splits on `:` and reads a 4-part `show:tmdb:{id}:{x}` key as
/// an episode, so the 5-part season key can never be mistaken for one. Season keys exist only in
/// the downloads domain and are never handed to Trakt.
public enum DownloadKey {
    public static func movie(tmdbID: Int) -> String {
        "movie:tmdb:\(tmdbID)"
    }

    public static func episode(showTmdbID: Int, season: Int, number: Int) -> String {
        "show:tmdb:\(showTmdbID):s\(season)e\(number)"
    }

    public static func season(showTmdbID: Int, season: Int) -> String {
        "show:tmdb:\(showTmdbID):season:\(season)"
    }
}
