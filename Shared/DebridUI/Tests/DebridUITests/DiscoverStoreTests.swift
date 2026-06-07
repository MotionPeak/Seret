import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

private final class FakeDiscover: DiscoverProviding, @unchecked Sendable {
    var nowPlayingResult: Result<[TMDBSearchResult], FakeError> = .success([])
    var byGenre: [Int: Result<[TMDBSearchResult], FakeError>] = [:]
    var defaultGenre: Result<[TMDBSearchResult], FakeError> = .success([])

    func nowPlaying() async throws -> [TMDBSearchResult] { try nowPlayingResult.get() }
    func movies(genreID: Int) async throws -> [TMDBSearchResult] {
        try (byGenre[genreID] ?? defaultGenre).get()
    }
}

private func movie(_ id: Int) -> TMDBSearchResult {
    TMDBSearchResult(id: id, title: "M\(id)", name: nil, releaseDate: "2020-01-01",
                     firstAirDate: nil, posterPath: "/p.jpg", overview: nil, voteAverage: 7)
}

@MainActor
@Suite struct DiscoverStoreTests {
    @Test func loadsRowsAndDropsEmptyOnes() async {
        let fake = FakeDiscover()
        fake.nowPlayingResult = .success([movie(1), movie(2)])
        fake.defaultGenre = .success([movie(3)])     // every genre returns one
        fake.byGenre[27] = .success([])              // …except Horror → empty, must be dropped
        let store = DiscoverStore(discover: fake)
        await store.load()

        #expect(store.state == .loaded)
        // Recently Released is first and tagged as movie hits.
        #expect(store.rows.first?.title == "Recently Released")
        #expect(store.rows.first?.hits.count == 2)
        #expect(store.rows.first?.hits.first?.kind == .movie)
        // The empty Horror row is dropped.
        #expect(!store.rows.contains { $0.title == "Horror" })
        #expect(store.rows.count >= 2)
    }

    @Test func failsWhenEverythingEmptyOrErrors() async {
        let fake = FakeDiscover()
        fake.nowPlayingResult = .failure(.boom)
        fake.defaultGenre = .success([])
        let store = DiscoverStore(discover: fake)
        await store.load()
        #expect(store.state == .failed)
        #expect(store.rows.isEmpty)
    }
}
