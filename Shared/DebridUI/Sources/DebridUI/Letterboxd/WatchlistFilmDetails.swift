import Foundation
import DebridCore

/// What the Apple TV Watchlist page knows about a film beyond its watchlist row: the TMDB facts
/// its rows are built from (genres, runtime, rating) and its header shows (synopsis, backdrop,
/// logo). One movie-details call per film, kept on disk by `WatchlistDetailsStore`.
public struct WatchlistFilmDetails: Sendable, Codable, Equatable {
    public let tmdbID: Int
    /// TMDB's own genre names ("Science Fiction") — the rows shorten them, the header does not.
    public let genres: [String]
    public let runtimeMinutes: Int?
    public let voteAverage: Double?
    /// Nil when TMDB did not say; a film with an unknown count is not filtered out of Highest Rated.
    public let voteCount: Int?
    public let overview: String?
    /// The textless plate when TMDB has one — the same choice the title page makes.
    public let backdropPath: String?
    public let logoPath: String?
    /// When this was read from TMDB. Entries older than the store's `maxAge` are fetched again.
    public let fetchedAt: Date

    public init(tmdbID: Int, genres: [String], runtimeMinutes: Int?, voteAverage: Double?,
                voteCount: Int?, overview: String?, backdropPath: String?, logoPath: String?,
                fetchedAt: Date) {
        self.tmdbID = tmdbID; self.genres = genres; self.runtimeMinutes = runtimeMinutes
        self.voteAverage = voteAverage; self.voteCount = voteCount; self.overview = overview
        self.backdropPath = backdropPath; self.logoPath = logoPath; self.fetchedAt = fetchedAt
    }

    public init(movie: TMDBMovieDetails, fetchedAt: Date) {
        self.init(tmdbID: movie.id, genres: movie.genres.map(\.name), runtimeMinutes: movie.runtime,
                  voteAverage: movie.voteAverage, voteCount: movie.voteCount,
                  overview: movie.overview,
                  backdropPath: movie.preferredBackdropPath ?? movie.backdropPath,
                  logoPath: movie.logoPath, fetchedAt: fetchedAt)
    }

    /// The same facts as the preview header's art, so a focused film's header can be drawn from
    /// the cache without a second details call (`TitleArtStore.seed`).
    public var titleArt: TitleArt {
        TitleArt(logoPath: logoPath, backdropPath: backdropPath, voteAverage: voteAverage,
                 genres: genres, runtimeMinutes: runtimeMinutes, seasonCount: nil)
    }
}
