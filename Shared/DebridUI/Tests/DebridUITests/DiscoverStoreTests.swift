import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

private final class FakeDiscover: DiscoverProviding, @unchecked Sendable {
    var nowPlayingResult: Result<[TMDBSearchResult], FakeError> = .success([])
    var popularMovie: Result<[TMDBSearchResult], FakeError> = .success([])
    var newMovie: Result<[TMDBSearchResult], FakeError> = .success([])
    var popularTV: Result<[TMDBSearchResult], FakeError> = .success([])
    var newTV: Result<[TMDBSearchResult], FakeError> = .success([])
    private(set) var newMovieWindow: (from: String, to: String)?

    func nowPlaying() async throws -> [TMDBSearchResult] { try nowPlayingResult.get() }
    func popularMoviesByGenre(_ id: Int) async throws -> [TMDBSearchResult] { try popularMovie.get() }
    func newMoviesByGenre(_ id: Int, from: String, to: String) async throws -> [TMDBSearchResult] {
        newMovieWindow = (from, to); return try newMovie.get()
    }
    func popularTVByGenre(_ id: Int) async throws -> [TMDBSearchResult] { try popularTV.get() }
    func newTVByGenre(_ id: Int, from: String, to: String) async throws -> [TMDBSearchResult] { try newTV.get() }
}

private func movie(_ id: Int) -> TMDBSearchResult {
    TMDBSearchResult(id: id, title: "M\(id)", name: nil, releaseDate: "2020-01-01",
                     firstAirDate: nil, posterPath: "/p.jpg", overview: nil, voteAverage: 7)
}

@MainActor
@Suite struct DiscoverStoreTests {
    @Test func movieSectionsInOrderWithCAMOnInTheatres() async {
        let fake = FakeDiscover()
        fake.nowPlayingResult = .success([movie(1)])
        fake.newMovie = .success([movie(2)])
        fake.popularMovie = .success([movie(3)])
        let store = DiscoverStore(kind: .movie, discover: fake)
        await store.load()
        #expect(store.state == .loaded)
        #expect(store.sections.map(\.title) == ["In Theatres", "New Releases", "Most Popular"])
        #expect(store.sections.first?.isCAM == true)
        #expect(store.sections.first?.rows.first?.hits.first?.kind == .movie)
        // New Releases / Most Popular have one row per movie genre (8).
        #expect(store.sections[1].rows.count == 8)
        #expect(store.sections[2].rows.count == 8)
        #expect(store.sections[1].rows.first?.title == "Action")
    }

    @Test func camIDsCoverInTheatresTitlesEverywhere() async {
        let fake = FakeDiscover()
        fake.nowPlayingResult = .success([movie(42)])   // In Theatres → CAM
        fake.newMovie = .success([movie(42), movie(7)])  // 42 also appears under a genre
        fake.popularMovie = .success([movie(9)])
        let store = DiscoverStore(kind: .movie, discover: fake)
        await store.load()
        #expect(store.camIDs.contains(42))
        #expect(!store.camIDs.contains(7))
        #expect(store.isCAM(movie(42)))     // tagged in New Releases too, not just In Theatres
        #expect(!store.isCAM(movie(9)))
    }

    @Test func emptyInTheatresSectionDropped() async {
        let fake = FakeDiscover()
        fake.nowPlayingResult = .success([])     // no In Theatres
        fake.newMovie = .success([movie(2)])
        fake.popularMovie = .success([movie(3)])
        let store = DiscoverStore(kind: .movie, discover: fake)
        await store.load()
        #expect(!store.sections.contains { $0.title == "In Theatres" })
        #expect(store.sections.map(\.title) == ["New Releases", "Most Popular"])
    }

    @Test func showHasNoInTheatres() async {
        let fake = FakeDiscover()
        fake.newTV = .success([movie(1)])
        fake.popularTV = .success([movie(2)])
        let store = DiscoverStore(kind: .show, discover: fake)
        await store.load()
        #expect(store.sections.map(\.title) == ["New Releases", "Most Popular"])
        #expect(store.sections.allSatisfy { !$0.isCAM })
        #expect(store.sections.first?.rows.first?.hits.first?.kind == .show)
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
        #expect(store.sections.isEmpty)
    }
}
