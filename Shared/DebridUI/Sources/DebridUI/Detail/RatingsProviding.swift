import DebridCore

/// Thin Sendable seam over OMDb ratings, so `DetailStore` is unit-testable without the network.
/// Mirrors `MediaDetailsProviding`.
public protocol RatingsProviding: Sendable {
    func ratings(imdbID: String) async throws -> OMDbRatings
}

/// Production conformance: cache-first, with a stale-entry fallback when the network fails.
public struct OMDbRatingsService: RatingsProviding {
    private let cache: OMDbRatingsCache
    private let fetch: @Sendable (String) async throws -> OMDbRatings

    public init(client: OMDbClient, cache: OMDbRatingsCache) {
        self.cache = cache
        self.fetch = { try await client.ratings(imdbID: $0) }
    }

    /// Test seam: inject the fetch directly.
    init(cache: OMDbRatingsCache, fetch: @escaping @Sendable (String) async throws -> OMDbRatings) {
        self.cache = cache
        self.fetch = fetch
    }

    public func ratings(imdbID: String) async throws -> OMDbRatings {
        if let hit = await cache.cached(imdbID: imdbID) { return hit }
        do {
            let fresh = try await fetch(imdbID)
            await cache.store(fresh, imdbID: imdbID)
            return fresh
        } catch {
            if let stale = await cache.stored(imdbID: imdbID) { return stale }
            throw error
        }
    }
}
