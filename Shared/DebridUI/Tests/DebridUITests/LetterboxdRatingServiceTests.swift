import Testing
import Foundation
import DebridCore
@testable import DebridUI

struct LetterboxdRatingServiceTests {
    private func cache(_ dir: URL, ttl: TimeInterval = 10_000) -> TTLFileCache<LetterboxdFilmRating?> {
        TTLFileCache(directory: dir, fileName: "letterboxd-ratings.json", ttl: ttl)
    }
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }
    private let sample = LetterboxdFilmRating(score: 4.38, count: 3_654_485)

    @Test func aScoreIsFetchedOnceAndThenServedFromTheCache() async throws {
        let calls = Counter()
        let service = LetterboxdRatingService(cache: cache(tempDir()), fetch: { _ in
            await calls.bump(); return self.sample
        })
        #expect(try await service.rating(forTMDB: 693134) == sample)
        #expect(try await service.rating(forTMDB: 693134) == sample)
        #expect(await calls.value == 1)
    }

    /// The load-bearing one. A film with no score, and every TV show, must record that answer or
    /// each detail open spends a 47 KB page re-learning it. "No score" has to survive the trip to
    /// disk and back as an ANSWER, not as an absent entry.
    @Test func noScoreIsRememberedAcrossInstancesRatherThanRefetched() async throws {
        let dir = tempDir()
        let calls = Counter()
        let fetch: @Sendable (Int) async throws -> LetterboxdFilmRating? = { _ in
            await calls.bump(); return nil
        }
        #expect(try await LetterboxdRatingService(cache: cache(dir), fetch: fetch)
            .rating(forTMDB: 1) == nil)
        #expect(try await LetterboxdRatingService(cache: cache(dir), fetch: fetch)
            .rating(forTMDB: 1) == nil)
        #expect(await calls.value == 1)
    }

    /// Letterboxd has no film at all for a TV show. That is permanent, so it is cached as "no
    /// score" rather than thrown at the screen on every open.
    @Test func aTitleWithNoLetterboxdFilmIsRecordedAsNoScore() async throws {
        let dir = tempDir()
        let calls = Counter()
        let fetch: @Sendable (Int) async throws -> LetterboxdFilmRating? = { _ in
            await calls.bump(); throw LetterboxdError.filmNotFound
        }
        #expect(try await LetterboxdRatingService(cache: cache(dir), fetch: fetch)
            .rating(forTMDB: 1396) == nil)
        #expect(try await LetterboxdRatingService(cache: cache(dir), fetch: fetch)
            .rating(forTMDB: 1396) == nil)
        #expect(await calls.value == 1)
    }

    /// A refusal says nothing about the film, so a known score must survive it.
    @Test func aTransientFailureFallsBackToAStoredScore() async throws {
        let c = cache(tempDir(), ttl: 0)   // everything is stale immediately
        await c.store(sample, key: "693134")
        let service = LetterboxdRatingService(cache: c, fetch: { _ in
            throw LetterboxdError.transient("cloudflare")
        })
        #expect(try await service.rating(forTMDB: 693134) == sample)
    }

    /// ...and with nothing stored it must surface, never be recorded as "no score".
    @Test func aTransientFailureWithNothingStoredRethrowsAndCachesNothing() async throws {
        let dir = tempDir()
        let service = LetterboxdRatingService(cache: cache(dir), fetch: { _ in
            throw LetterboxdError.transient("cloudflare")
        })
        await #expect(throws: LetterboxdError.self) { _ = try await service.rating(forTMDB: 1) }
        #expect(await cache(dir).stored("1") == nil)
    }

    private actor Counter {
        private(set) var value = 0
        func bump() { value += 1 }
    }
}
