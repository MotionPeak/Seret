import Foundation
import DebridCore

public extension PreviewSubject {
    /// The preview header's description of a watchlist film: its title page's id (so the art store
    /// keys it), its cached synopsis and backdrop, and the page's tags. A film that resolved to no
    /// TMDB title says so instead.
    ///
    /// One definition for every page that shows watchlist films — the Watchlist page and Home's
    /// picks rows — so one film never gets two different headers.
    static func watchlist(_ entry: WatchlistEntry, details: WatchlistFilmDetails?,
                          tags: [String]) -> PreviewSubject {
        guard let item = MediaItem.watchlistMovie(entry) else {
            let stub = MediaItem(id: "watchlist:\(entry.slug)", kind: .movie,
                                 title: WatchlistName.stripYear(from: entry.name), year: entry.year,
                                 sources: [], seasons: [], tmdbID: nil, posterPath: entry.posterPath)
            return PreviewSubject(item: stub, overview: nil, backdropPath: nil,
                                  tags: ["No TMDB match"], showsKind: false)
        }
        return PreviewSubject(item: item, overview: details?.overview, backdropPath: details?.backdropPath,
                              tags: tags, showsKind: false)
    }
}
