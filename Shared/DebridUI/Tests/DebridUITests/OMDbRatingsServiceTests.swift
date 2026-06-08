import Testing
import Foundation
import DebridCore
@testable import DebridUI

struct OMDbRatingsServiceTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }
    private let sample = OMDbRatings(imdb: 8.7, rottenTomatoes: 88, metacritic: 73)

    @Test func cacheMissFetchesAndStores() async throws {
        let cache = OMDbRatingsCache(directory: tempDir(), ttl: 10_000)
        let calls = Counter()
        let service = OMDbRatingsService(cache: cache, fetch: { _ in
            await calls.bump(); return self.sample
        })
        let r = try await service.ratings(imdbID: "tt1")
        #expect(r == sample)
        #expect(await calls.value == 1)
        // second call served from cache, no extra fetch
        _ = try await service.ratings(imdbID: "tt1")
        #expect(await calls.value == 1)
    }

    @Test func networkFailureFallsBackToStored() async throws {
        let cache = OMDbRatingsCache(directory: tempDir(), ttl: 0)   // everything is "stale" immediately
        await cache.store(sample, imdbID: "tt1")
        let service = OMDbRatingsService(cache: cache, fetch: { _ in
            throw OMDbError.notFound("boom")
        })
        let r = try await service.ratings(imdbID: "tt1")
        #expect(r == sample)   // stale fallback
    }

    @Test func failureWithNoEntryRethrows() async {
        let cache = OMDbRatingsCache(directory: tempDir(), ttl: 10_000)
        let service = OMDbRatingsService(cache: cache, fetch: { _ in
            throw OMDbError.notFound("boom")
        })
        await #expect(throws: OMDbError.self) { _ = try await service.ratings(imdbID: "tt1") }
    }

    private actor Counter {
        private(set) var value = 0
        func bump() { value += 1 }
    }
}
