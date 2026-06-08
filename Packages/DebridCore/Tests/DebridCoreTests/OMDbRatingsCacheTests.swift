import Testing
import Foundation
@testable import DebridCore

struct OMDbRatingsCacheTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }
    private let sample = OMDbRatings(imdb: 8.7, rottenTomatoes: 88, metacritic: 73)

    @Test func freshEntryIsReturned() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cache = OMDbRatingsCache(directory: tempDir(), ttl: 100, now: { now })
        await cache.store(sample, imdbID: "tt1")
        #expect(await cache.cached(imdbID: "tt1") == sample)
    }

    // Stored at T by one instance; a second instance whose clock is T+200 (> ttl) reads it back
    // from disk and sees it as expired. Also exercises disk persistence + the injected clock.
    @Test func expiredEntryNotReturnedByCached() async {
        let dir = tempDir()
        let stored = OMDbRatingsCache(directory: dir, ttl: 100, now: { Date(timeIntervalSince1970: 1_000_000) })
        await stored.store(sample, imdbID: "tt1")
        let later = OMDbRatingsCache(directory: dir, ttl: 100, now: { Date(timeIntervalSince1970: 1_000_200) })
        #expect(await later.cached(imdbID: "tt1") == nil)
    }

    @Test func storedReturnsExpiredEntry() async {
        let dir = tempDir()
        let stored = OMDbRatingsCache(directory: dir, ttl: 100, now: { Date(timeIntervalSince1970: 1_000_000) })
        await stored.store(sample, imdbID: "tt1")
        let later = OMDbRatingsCache(directory: dir, ttl: 100, now: { Date(timeIntervalSince1970: 1_000_200) })
        #expect(await later.stored(imdbID: "tt1") == sample)   // stale, but available as fallback
    }

    @Test func missingEntryIsNil() async {
        let cache = OMDbRatingsCache(directory: tempDir(), ttl: 100, now: { Date() })
        #expect(await cache.cached(imdbID: "nope") == nil)
        #expect(await cache.stored(imdbID: "nope") == nil)
    }

    @Test func persistsAcrossInstances() async {
        let dir = tempDir()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let a = OMDbRatingsCache(directory: dir, ttl: 10_000, now: { now })
        await a.store(sample, imdbID: "tt1")
        let b = OMDbRatingsCache(directory: dir, ttl: 10_000, now: { now })
        #expect(await b.cached(imdbID: "tt1") == sample)
    }
}
