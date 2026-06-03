import DebridCore

/// Thin Sendable seam over the brain's TMDB detail calls, so `DetailStore` is unit-testable
/// without the network. Mirrors 7b-i's `LibraryProviding`.
protocol MediaDetailsProviding: Sendable {
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails]
}

/// Production conformance — delegates straight to `TMDBClient`.
struct TMDBDetailsService: MediaDetailsProviding {
    let client: TMDBClient
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
        try await client.movieDetails(id: tmdbID)
    }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
        try await client.tvDetails(id: tmdbID)
    }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] {
        try await client.tvSeasonDetails(tvID: tvID, season: season).episodes
    }
}
