import DebridCore

/// Searches TMDB for titles. Thin seam over `TMDBClient` so `SearchStore` is testable.
public protocol SearchProviding: Sendable {
    func searchMovie(query: String, year: Int?) async throws -> [TMDBSearchResult]
    func searchTV(query: String, firstAirYear: Int?) async throws -> [TMDBSearchResult]
}

public struct TMDBSearchService: SearchProviding {
    let client: TMDBClient
    public init(client: TMDBClient) { self.client = client }
    public func searchMovie(query: String, year: Int?) async throws -> [TMDBSearchResult] {
        try await client.searchMovie(query: query, year: year)
    }
    public func searchTV(query: String, firstAirYear: Int?) async throws -> [TMDBSearchResult] {
        try await client.searchTV(query: query, firstAirYear: firstAirYear)
    }
}
