import Vapor
import DebridCore

/// `/api/detail/:id` — the rich movie detail payload for the native-parity title page.
/// Assembles the persisted library entry with on-demand TMDB (details + credits + recommendations)
/// and OMDb ratings. Enrichment runs concurrently and every section degrades to empty on failure,
/// so the page always renders at least title/backdrop/versions.
func registerDetailRoutes(_ app: Application) {
    app.get("api", "detail", ":id") { req async throws -> DetailDTO in
        let id = try req.parameters.require("id")
        let lib = req.application.library
        guard let item = await lib.item(id: id) else { throw Abort(.notFound) }

        var backdropPath = item.backdropPath
        var overview = item.overview
        var runtime: Int?
        var genres: [String] = []
        var director: String?
        var voteAverage: Double?
        var ratings: RatingsDTO?
        var cast: [CastDTO] = []
        var similar: [SimilarDTO] = []

        if let tmdbID = item.tmdbID {
            let tmdb = req.application.tmdb
            // Details, credits and recommendations in parallel; each degrades to nil on failure.
            async let detailsTask = tmdb.movieDetails(id: tmdbID)
            async let creditsTask = tmdb.movieCredits(id: tmdbID)
            async let recsTask = tmdb.recommendedMovies(id: tmdbID)
            let details = try? await detailsTask
            let credits = try? await creditsTask
            let recs = try? await recsTask

            if let d = details {
                runtime = d.runtime
                genres = d.genres.map(\.name)
                voteAverage = d.voteAverage
                backdropPath = d.backdropPath ?? backdropPath
                overview = d.overview ?? overview
            }
            if let credits {
                director = credits.director
                cast = credits.cast.prefix(20).map {
                    CastDTO(name: $0.name, character: $0.character, profilePath: $0.profilePath)
                }
            }
            if let recs {
                // Owned suggestions link to their detail page; the rest render as static posters.
                let ownedByTMDB = Dictionary(
                    await lib.items.compactMap { i in i.tmdbID.map { ($0, i.id) } },
                    uniquingKeysWith: { first, _ in first })
                similar = recs.prefix(18).map {
                    SimilarDTO(title: $0.displayTitle, year: $0.year,
                               posterPath: $0.posterPath, ownedID: ownedByTMDB[$0.id])
                }
            }
            // Ratings need the IMDb id (from details) and a configured OMDb client.
            if let imdbID = details?.imdbID, let omdb = req.application.ratings,
               let r = try? await omdb.ratings(imdbID: imdbID), r.hasAny {
                ratings = RatingsDTO(imdb: r.imdb, rottenTomatoes: r.rottenTomatoes, metacritic: r.metacritic)
            }
        }

        let best = item.sources.best?.parsed
        let qualityChips = [best?.resolution, best?.source, best?.videoCodec, best?.audioCodec]
            .compactMap { $0 }
        let versions = VersionDTO.list(for: item)

        return DetailDTO(
            id: item.id, title: item.title, year: item.year,
            posterPath: item.posterPath, backdropPath: backdropPath, overview: overview,
            runtime: runtime, genres: genres, director: director, voteAverage: voteAverage,
            qualityChips: qualityChips, bestVersionIndex: versions.first?.index ?? 0,
            versions: versions, ratings: ratings, cast: cast, similar: similar)
    }
}
