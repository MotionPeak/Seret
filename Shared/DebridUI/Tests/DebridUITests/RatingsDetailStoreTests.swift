import Testing
import Foundation
import DebridCore
@testable import DebridUI

@MainActor
struct RatingsDetailStoreTests {
    // Minimal MediaDetailsProviding that returns a movie carrying an imdbID.
    struct StubDetails: MediaDetailsProviding {
        func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
            TMDBMovieDetails(id: tmdbID, title: "M", releaseDate: "2020-01-01", overview: "o",
                             posterPath: nil, backdropPath: nil, runtime: 100, genres: [],
                             voteAverage: 7.0, originalLanguage: "en", imdbID: "tt123")
        }
        func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw CancellationError() }
        func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
    }
    struct OKRatings: RatingsProviding {
        let value: OMDbRatings
        func ratings(imdbID: String) async throws -> OMDbRatings { value }
    }
    struct FailRatings: RatingsProviding {
        func ratings(imdbID: String) async throws -> OMDbRatings { throw OMDbError.notFound("x") }
    }

    private func movie() -> MediaItem {
        MediaItem(id: "1", kind: .movie, title: "M", year: 2020, sources: [], seasons: [],
                  tmdbID: 99, overview: nil)
    }

    @Test func loadPopulatesRatings() async {
        let sample = OMDbRatings(imdb: 8.7, rottenTomatoes: 88, metacritic: 73)
        let store = DetailStore(item: movie(), details: StubDetails(), watch: nil,
                                ratings: OKRatings(value: sample))
        await store.load()
        #expect(store.ratings == sample)
        #expect(store.ratingsState == .loaded)
    }

    @Test func ratingsFailureDegradesGracefully() async {
        let store = DetailStore(item: movie(), details: StubDetails(), watch: nil,
                                ratings: FailRatings())
        await store.load()
        #expect(store.ratings == nil)
        #expect(store.ratingsState == .failed)
        #expect(store.richState == .loaded)   // the rest of the screen still loads
    }

    @Test func noProviderLeavesRatingsIdle() async {
        let store = DetailStore(item: movie(), details: StubDetails(), watch: nil)
        await store.load()
        #expect(store.ratings == nil)
        #expect(store.ratingsState == .idle)
    }
}


/// OMDb saying it does not know a title is an ANSWER, and it keeps giving the same one. Not
/// recording it meant every title OMDb has no entry for — and a library holds plenty — spent a
/// fresh request on every single detail open, against a free quota of a thousand a day.
@Suite struct OMDbMissCachingTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "omdb-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private actor Calls {
        private(set) var count = 0
        func bump() { count += 1 }
    }

    @Test func aTitleOMDbDoesNotKnowIsAskedAboutOnce() async throws {
        let calls = Calls()
        let cache = OMDbRatingsCache(directory: tempDir())
        let service = OMDbRatingsService(cache: cache) { _ in
            await calls.bump()
            throw OMDbError.notFound("Incorrect IMDb ID.")
        }

        let first = try await service.ratings(imdbID: "tt404")
        let second = try await service.ratings(imdbID: "tt404")

        #expect(first.hasAny == false)
        #expect(second.hasAny == false)
        #expect(await calls.count == 1)
    }

    /// A spent quota also comes back as `Response:False`, and it is a fact about US, not the
    /// title. Caching it would blank the ratings for the ENTIRE library for a week the first time
    /// the thousand-a-day free quota ran out.
    @Test func aSpentQuotaIsNotCachedAsAMiss() async throws {
        let calls = Calls()
        let cache = OMDbRatingsCache(directory: tempDir())
        let service = OMDbRatingsService(cache: cache) { _ in
            await calls.bump()
            throw OMDbError.notFound("Request limit reached!")
        }

        await #expect(throws: (any Error).self) { _ = try await service.ratings(imdbID: "tt1") }
        await #expect(throws: (any Error).self) { _ = try await service.ratings(imdbID: "tt1") }

        #expect(await calls.count == 2)      // asked again, as it must be
    }

    /// A title that once had scores must not lose them to a later "not found".
    @Test func aStoredRatingSurvivesALaterNotFound() async throws {
        let cache = OMDbRatingsCache(directory: tempDir(), ttl: 0)   // stale immediately
        let real = OMDbRatings(imdb: 8.7, rottenTomatoes: 88, metacritic: 73)
        await cache.store(real, imdbID: "tt1")
        let service = OMDbRatingsService(cache: cache) { _ in
            throw OMDbError.notFound("Movie not found!")
        }
        #expect(try await service.ratings(imdbID: "tt1") == real)
    }

    /// A transport failure says nothing about the title and must NEVER be cached — one blip would
    /// otherwise suppress a real rating for the whole TTL.
    @Test func aTransportFailureIsNotCachedAsAMiss() async throws {
        enum Boom: Error { case offline }
        let calls = Calls()
        let cache = OMDbRatingsCache(directory: tempDir())
        let service = OMDbRatingsService(cache: cache) { _ in
            await calls.bump()
            throw Boom.offline
        }

        await #expect(throws: (any Error).self) { _ = try await service.ratings(imdbID: "tt1") }
        await #expect(throws: (any Error).self) { _ = try await service.ratings(imdbID: "tt1") }

        #expect(await calls.count == 2)      // asked again, as it must be
    }
}
