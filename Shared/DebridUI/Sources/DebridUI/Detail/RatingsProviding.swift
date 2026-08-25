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

    /// OMDb answers `Response:False` for two very different situations: it has no such title, and
    /// it is refusing to serve us at all (bad key, daily quota spent). Only the first is a fact
    /// about the title. Caching the second would blank the ratings for the ENTIRE library for a
    /// week, the first time the thousand-a-day free quota ran out.
    static func meansTitleIsUnknown(_ message: String) -> Bool {
        let m = message.lowercased()
        return m.contains("not found") || m.contains("incorrect imdb id")
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
        } catch let OMDbError.notFound(message) where Self.meansTitleIsUnknown(message) {
            // OMDb saying it has no such title is an ANSWER, and it will keep giving the same one.
            // Not recording it meant every title OMDb has no entry for — and a library holds
            // plenty — spent a fresh request on every single detail open, against a free quota of
            // a thousand a day. An all-nil result is exactly how "no scores" is already
            // represented (`hasAny` is false), so the screen renders identically.
            //
            // A stored rating still wins: a title that once had scores must not lose them to a
            // later "not found".
            if let stale = await cache.stored(imdbID: imdbID) { return stale }
            let none = OMDbRatings(imdb: nil, rottenTomatoes: nil, metacritic: nil)
            await cache.store(none, imdbID: imdbID)
            return none
        } catch {
            // A transport failure says nothing about the title — never cache it, or one blip would
            // suppress a real rating for the whole TTL.
            if let stale = await cache.stored(imdbID: imdbID) { return stale }
            throw error
        }
    }
}
