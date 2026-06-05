import DebridCore

/// Thin Sendable seam over the brain's TMDB detail calls, so `DetailStore` is unit-testable
/// without the network. Mirrors 7b-i's `LibraryProviding`.
public protocol MediaDetailsProviding: Sendable {
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails]
}

/// Production conformance — delegates straight to `TMDBClient`.
public struct TMDBDetailsService: MediaDetailsProviding {
    let client: TMDBClient
    public init(client: TMDBClient) { self.client = client }
    public func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
        try await client.movieDetails(id: tmdbID)
    }
    public func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
        try await client.tvDetails(id: tmdbID)
    }
    public func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] {
        try await client.tvSeasonDetails(tvID: tvID, season: season).episodes
    }
}
