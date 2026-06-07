import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

private final class FakeDiscover: DiscoverProviding, @unchecked Sendable {
    var popularMoviesResult: Result<[TMDBSearchResult], FakeError> = .success([])
    var popularTVResult: Result<[TMDBSearchResult], FakeError> = .success([])
    var nowPlayingResult: Result<[TMDBSearchResult], FakeError> = .success([])
    var newReleasesResult: Result<[TMDBSearchResult], FakeError> = .success([])
    var movieGenre: Result<[TMDBSearchResult], FakeError> = .success([])
    var tvGenre: Result<[TMDBSearchResult], FakeError> = .success([])
    private(set) var newReleasesWindow: (from: String, to: String)?

    func popularMovies() async throws -> [TMDBSearchResult] { try popularMoviesResult.get() }
    func popularTV() async throws -> [TMDBSearchResult] { try popularTVResult.get() }
    func nowPlaying() async throws -> [TMDBSearchResult] { try nowPlayingResult.get() }
    func newReleases(from: String, to: String) async throws -> [TMDBSearchResult] {
        newReleasesWindow = (from, to); return try newReleasesResult.get()
    }
    func moviesByGenre(_ id: Int) async throws -> [TMDBSearchResult] { try movieGenre.get() }
    func tvByGenre(_ id: Int) async throws -> [TMDBSearchResult] { try tvGenre.get() }
}

private func movie(_ id: Int) -> TMDBSearchResult {
    TMDBSearchResult(id: id, title: "M\(id)", name: nil, releaseDate: "2020-01-01",
                     firstAirDate: nil, posterPath: "/p.jpg", overview: nil, voteAverage: 7)
}

@MainActor
@Suite struct DiscoverStoreTests {
    @Test func movieStoreBuildsRowsAndDropsEmpty() async {
        let fake = FakeDiscover()
        fake.popularMoviesResult = .success([movie(1)])
        fake.nowPlayingResult = .success([movie(2)])
        fake.newReleasesResult = .success([movie(3)])
        fake.movieGenre = .success([movie(4)])   // every genre returns one
        let store = DiscoverStore(kind: .movie, discover: fake)
        await store.load()
        #expect(store.state == .loaded)
        #expect(store.rows.first?.title == "Popular")
        #expect(store.rows.contains { $0.title == "In Theatres" })
        #expect(store.rows.contains { $0.title == "New Releases" })
        #expect(store.rows.first?.hits.first?.kind == .movie)
    }

    @Test func movieStorePassesReleaseWindowAround45And300Days() async {
        let fake = FakeDiscover()
        fake.newReleasesResult = .success([movie(3)])
        // Fixed "now" = 2026-06-07 00:00 UTC → from = -300d, to = -45d (formatter is UTC).
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 7
        comps.timeZone = TimeZone(identifier: "UTC")
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let fixed = cal.date(from: comps)!
        let store = DiscoverStore(kind: .movie, discover: fake, now: { fixed })
        await store.load()
        #expect(fake.newReleasesWindow?.from == "2025-08-11")   // 2026-06-07 − 300d
        #expect(fake.newReleasesWindow?.to == "2026-04-23")     // 2026-06-07 − 45d
    }

    @Test func showStoreBuildsPopularPlusGenresNoMovieRows() async {
        let fake = FakeDiscover()
        fake.popularTVResult = .success([movie(1)])
        fake.tvGenre = .success([movie(2)])
        let store = DiscoverStore(kind: .show, discover: fake)
        await store.load()
        #expect(store.state == .loaded)
        #expect(store.rows.first?.title == "Popular")
        #expect(!store.rows.contains { $0.title == "In Theatres" })   // movies-only
        #expect(store.rows.first?.hits.first?.kind == .show)
    }

    @Test func failsWhenEverythingEmpty() async {
        let store = DiscoverStore(kind: .movie, discover: FakeDiscover())
        await store.load()
        #expect(store.state == .failed)
        #expect(store.rows.isEmpty)
    }
}
