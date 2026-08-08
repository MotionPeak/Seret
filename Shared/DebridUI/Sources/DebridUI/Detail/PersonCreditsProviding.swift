import DebridCore

/// The seam the person page loads through, so `PersonStore` can be tested without a network.
public protocol PersonCreditsProviding: Sendable {
    func person(tmdbID: Int) async throws -> TMDBPersonDetails
}

/// Production conformance — delegates straight to `TMDBClient`.
public struct TMDBPersonService: PersonCreditsProviding {
    let client: TMDBClient
    public init(client: TMDBClient) { self.client = client }
    public func person(tmdbID: Int) async throws -> TMDBPersonDetails {
        try await client.person(id: tmdbID)
    }
}
