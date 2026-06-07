import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

private final class FakeSearch: SearchProviding {
    let movies: Result<[TMDBSearchResult], FakeError>
    let tv: Result<[TMDBSearchResult], FakeError>
    init(movies: Result<[TMDBSearchResult], FakeError> = .success([]),
         tv: Result<[TMDBSearchResult], FakeError> = .success([])) {
        self.movies = movies; self.tv = tv
    }
    func searchMovie(query: String, year: Int?) async throws -> [TMDBSearchResult] { try movies.get() }
    func searchTV(query: String, firstAirYear: Int?) async throws -> [TMDBSearchResult] { try tv.get() }
}

@MainActor
@Suite struct SearchStoreTests {
    func result(_ id: Int, _ title: String, vote: Double) -> TMDBSearchResult {
        TMDBSearchResult(id: id, title: title, name: nil, releaseDate: "2020-01-01",
                         firstAirDate: nil, posterPath: nil, overview: nil, voteAverage: vote)
    }

    @Test func emptyQueryStaysIdleAndClearsResults() async {
        let store = SearchStore(search: FakeSearch(movies: .success([result(1, "X", vote: 9)])))
        await store.search(query: "   ")
        #expect(store.state == .idle)
        #expect(store.results.isEmpty)
    }

    @Test func mergesMoviesAndTVBestVoteFirst() async {
        let store = SearchStore(search: FakeSearch(
            movies: .success([result(1, "Low", vote: 3)]),
            tv: .success([result(2, "High", vote: 8)])))
        await store.search(query: "matrix")
        #expect(store.state == .results)
        #expect(store.results.first?.result.id == 2)   // higher vote first
        #expect(store.results.first?.kind == .show)    // the TV hit
        #expect(store.results.count == 2)
        #expect(store.results.last?.kind == .movie)
    }

    @Test func movieKindReturnsOnlyMovieHits() async {
        let store = SearchStore(search: FakeSearch(
            movies: .success([result(1, "Mov", vote: 5)]),
            tv: .success([result(2, "Show", vote: 9)])))
        await store.search(query: "x", kind: .movie)
        #expect(store.results.count == 1)
        #expect(store.results.first?.kind == .movie)
        #expect(store.results.first?.result.id == 1)
    }

    @Test func showKindReturnsOnlyShowHits() async {
        let store = SearchStore(search: FakeSearch(
            movies: .success([result(1, "Mov", vote: 9)]),
            tv: .success([result(2, "Show", vote: 5)])))
        await store.search(query: "x", kind: .show)
        #expect(store.results.count == 1)
        #expect(store.results.first?.kind == .show)
    }

    @Test func noHitsIsEmpty() async {
        let store = SearchStore(search: FakeSearch())
        await store.search(query: "zzz")
        #expect(store.state == .empty)
    }

    @Test func failureSurfacesFailed() async {
        let store = SearchStore(search: FakeSearch(movies: .failure(.boom), tv: .failure(.boom)))
        await store.search(query: "matrix")
        if case .failed = store.state {} else { Issue.record("expected failed") }
    }
}
