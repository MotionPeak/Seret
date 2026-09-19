import Foundation
import DebridCore

public extension MediaItem {
    /// The title page a watchlist film opens.
    ///
    /// A stub rather than a library item: the watchlist knows a TMDB id and a poster and nothing
    /// else, and the unified title page fills the rest in from TMDB. It carries no sources, which
    /// is exactly right — a film on the watchlist is one you have not necessarily got yet.
    ///
    /// One definition because both the grid tile and the randomiser's result need it, and an id
    /// built two slightly different ways would push two different pages for the same film.
    static func watchlistMovie(_ entry: WatchlistEntry) -> MediaItem? {
        guard let tmdbID = entry.tmdbID else { return nil }
        return MediaItem(id: "movie:tmdb:\(tmdbID)", kind: .movie,
                         title: WatchlistName.stripYear(from: entry.name), year: entry.year,
                         sources: [], seasons: [], tmdbID: tmdbID, posterPath: entry.posterPath)
    }
}
