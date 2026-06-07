import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

private final class FakeDiscover: DiscoverProviding, @unchecked Sendable {
    var nowPlayingResult: Result<[TMDBSearchResult], FakeError> = .success([])
    var trendingMovie: Result<[TMDBSearchResult], FakeError> = .success([])
    var newMovie: Result<[TMDBSearchResult], FakeError> = .success([])
    var topRatedMovie: Result<[TMDBSearchResult], FakeError> = .success([])
    var trendingTV: Result<[TMDBSearchResult], FakeError> = .success([])
    var newTV: Result<[TMDBSearchResult], FakeError> = .success([])
    var topRatedTV: Result<[TMDBSearchResult], FakeError> = .success([])
    private(set) var newMovieWindow: (from: String, to: String)?

    func nowPlaying() async throws -> [TMDBSearchResult] { try nowPlayingResult.get() }
    func trendingMoviesByGenre(_ id: Int) async throws -> [TMDBSearchResult] { try trendingMovie.get() }
    func newMoviesByGenre(_ id: Int, from: String, to: String) async throws -> [TMDBSearchResult] {
        newMovieWindow = (from, to); return try newMovie.get()
    }
    func topRatedMoviesByGenre(_ id: Int) async throws -> [TMDBSearchResult] { try topRatedMovie.get() }
    func trendingTVByGenre(_ id: Int) async throws -> [TMDBSearchResult] { try trendingTV.get() }
    func newTVByGenre(_ id: Int, from: String, to: String) async throws -> [TMDBSearchResult] { try newTV.get() }
    func topRatedTVByGenre(_ id: Int) async throws -> [TMDBSearchResult] { try topRatedTV.get() }
}

private func movie(_ id: Int) -> TMDBSearchResult {
    TMDBSearchResult(id: id, title: "M\(id)", name: nil, releaseDate: "2020-01-01",
                     firstAirDate: nil, posterPath: "/p.jpg", overview: nil, voteAverage: 7)
}

@MainActor
@Suite struct DiscoverStoreTests {
    @Test func movieLoadsAllThreeSegmentsAsGenreRows() async {
        let fake = FakeDiscover()
        fake.trendingMovie = .success([movie(1)])
        fake.newMovie = .success([movie(2)])
        fake.topRatedMovie = .success([movie(3)])
        let store = DiscoverStore(kind: .movie, discover: fake)
        await store.load()
        #expect(store.state == .loaded)
        #expect(store.rowsBySegment[.trending]?.count == 8)   // one row per movie genre
        #expect(store.rowsBySegment[.newReleases]?.count == 8)
        #expect(store.rowsBySegment[.popular]?.count == 8)
        // Default segment is Trending; `rows` follows the selection.
        #expect(store.selectedSegment == .trending)
        #expect(store.rows.first?.hits.first?.result.id == 1)
        store.select(.popular)
        #expect(store.rows.first?.hits.first?.result.id == 3)
    }

    @Test func camIDsFromNowPlaying() async {
        let fake = FakeDiscover()
        fake.trendingMovie = .success([movie(1)])
        fake.nowPlayingResult = .success([movie(1), movie(9)])
        let store = DiscoverStore(kind: .movie, discover: fake)
        await store.load()
        #expect(store.camIDs == [1, 9])
        #expect(store.isCAM(movie(1)))
        #expect(!store.isCAM(movie(2)))
    }

    @Test func showHasNoNowPlayingButStillSegments() async {
        let fake = FakeDiscover()
        fake.trendingTV = .success([movie(1)])
        fake.topRatedTV = .success([movie(2)])
        let store = DiscoverStore(kind: .show, discover: fake)
        await store.load()
        #expect(store.state == .loaded)
        #expect(store.camIDs.isEmpty)
        #expect(store.rowsBySegment[.trending]?.first?.hits.first?.kind == .show)
        #expect(store.rowsBySegment[.popular]?.count == 7)   // tv genres
    }

    @Test func newReleasesWindowIs45To300DaysBack() async {
        let fake = FakeDiscover()
        fake.newMovie = .success([movie(2)])
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 7; comps.timeZone = TimeZone(identifier: "UTC")
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let fixed = cal.date(from: comps)!
        let store = DiscoverStore(kind: .movie, discover: fake, now: { fixed })
        await store.load()
        #expect(fake.newMovieWindow?.from == "2025-08-11")
        #expect(fake.newMovieWindow?.to == "2026-04-23")
    }

    @Test func failsWhenEverythingEmpty() async {
        let store = DiscoverStore(kind: .movie, discover: FakeDiscover())
        await store.load()
        #expect(store.state == .failed)
    }
}
