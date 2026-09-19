import Foundation

/// Persistent, TTL'd cache of OMDb ratings keyed by IMDb id. Keeps us well under OMDb's 1,000/day
/// free quota: a given title costs about one fetch per TTL window.
///
/// The TTL and stale-fallback rules live in `TTLFileCache`, which the Letterboxd ratings cache is
/// built on too — one implementation of those rules rather than two that can drift. This type is
/// the naming layer: it says the key is an IMDb id and which file the entries belong in.
public struct OMDbRatingsCache: Sendable {
    private let cache: TTLFileCache<OMDbRatings>

    /// - Parameters:
    ///   - ttl: how long an entry stays "fresh" (default 7 days).
    ///   - now: injectable clock for testing.
    public init(directory: URL,
                ttl: TimeInterval = 7 * 24 * 60 * 60,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.cache = TTLFileCache(directory: directory,
                                  fileName: "omdb-ratings.json",
                                  ttl: ttl,
                                  now: now)
    }

    /// Fresh entry only (within TTL), else nil.
    public func cached(imdbID: String) async -> OMDbRatings? { await cache.cached(imdbID) }

    /// Any stored entry regardless of age — the offline/stale fallback.
    public func stored(imdbID: String) async -> OMDbRatings? { await cache.stored(imdbID) }

    public func store(_ ratings: OMDbRatings, imdbID: String) async {
        await cache.store(ratings, key: imdbID)
    }
}
