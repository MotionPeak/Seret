import DebridCore
import Foundation

/// Thin Sendable seam over Letterboxd's community score, so `DetailStore` is unit-testable without
/// the network. Mirrors `RatingsProviding`.
///
/// Keyed by TMDB id rather than IMDb id, because that is the only id Letterboxd can be reached by.
public protocol LetterboxdRatingProviding: Sendable {
    /// Nil when there is no score to show — the film has none yet, or Letterboxd has no such film.
    func rating(forTMDB id: Int) async throws -> LetterboxdFilmRating?
}

/// Production conformance: cache-first, with a stale-entry fallback when the network fails.
///
/// One score costs a ~47 KB page, so what is cached matters more here than it does for OMDb: every
/// settled answer is recorded, including the absence of a score. Without that, every TV show and
/// every unreleased film would re-fetch a page on each title-page open, forever.
public struct LetterboxdRatingService: LetterboxdRatingProviding {
    private let cache: TTLFileCache<LetterboxdFilmRating?>
    private let fetch: @Sendable (Int) async throws -> LetterboxdFilmRating?

    public init(client: LetterboxdRatingsClient, cache: TTLFileCache<LetterboxdFilmRating?>) {
        self.cache = cache
        self.fetch = { try await client.rating(forTMDB: $0) }
    }

    /// Composition seam — also how the tests inject a fetch without a network.
    init(cache: TTLFileCache<LetterboxdFilmRating?>,
         fetch: @escaping @Sendable (Int) async throws -> LetterboxdFilmRating?) {
        self.cache = cache
        self.fetch = fetch
    }

    public func rating(forTMDB id: Int) async throws -> LetterboxdFilmRating? {
        let key = String(id)

        // The double optional is the point: the outer one is "have we an answer", the inner is
        // "is that answer a score". A cached nil is an answer and must not trigger a re-fetch.
        if let answer = await cache.cached(key) { return answer }

        do {
            let fresh = try await fetch(id)
            await cache.store(fresh, key: key)
            return fresh
        } catch LetterboxdError.filmNotFound {
            // Letterboxd indexes films only, so every show lands here — permanently. Recording it
            // is what stops a show costing a request on every open.
            //
            // A stored score still wins: a film must not lose one to a later lookup failure.
            if let stale = await cache.stored(key) { return stale }
            await cache.store(nil, key: key)
            return nil
        } catch {
            // A refusal or a dead network says nothing about the film — never record it, or one
            // blip would suppress a real score for the whole TTL.
            if let stale = await cache.stored(key) { return stale }
            throw error
        }
    }
}
