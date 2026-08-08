import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

private func part(_ id: Int, _ title: String, _ date: String) -> TMDBSearchResult {
    TMDBSearchResult(id: id, title: title, name: nil, releaseDate: date, firstAirDate: nil,
                     posterPath: "/\(id).jpg", overview: nil, voteAverage: nil)
}

private final class FranchiseDetails: MediaDetailsProviding {
    let ref: TMDBCollectionRef?
    let collectionResult: TMDBCollection?
    init(ref: TMDBCollectionRef?, collection: TMDBCollection?) {
        self.ref = ref; self.collectionResult = collection
    }
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
        TMDBMovieDetails(id: tmdbID, title: "The Hunger Games", releaseDate: "2012-03-12",
                         overview: "o", posterPath: "/p.jpg", backdropPath: "/b.jpg",
                         runtime: 142, genres: [], voteAverage: 7.2, originalLanguage: "en",
                         imdbID: "tt1392170", cast: [], directors: [], similar: [],
                         collection: ref)
    }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw FakeError.boom }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
    func collection(id: Int) async throws -> TMDBCollection? {
        guard let collectionResult else { throw FakeError.boom }
        return collectionResult
    }
}

private let hungerGamesRef = TMDBCollectionRef(id: 131635, name: "The Hunger Games Collection",
                                               posterPath: "/c.jpg", backdropPath: nil)

private let hungerGames = TMDBCollection(
    id: 131635, name: "The Hunger Games Collection", overview: nil, posterPath: "/c.jpg",
    backdropPath: nil,
    parts: [part(101299, "Catching Fire", "2013-11-15"),
            part(695721, "The Ballad of Songbirds & Snakes", "2023-11-15"),
            part(70160, "The Hunger Games", "2012-03-12"),
            part(1233413, "Sunrise on the Reaping", "2099-11-20"),   // not out yet
            part(131634, "Mockingjay - Part 1", "2014-11-18"),
            part(131631, "Mockingjay - Part 2", "2015-11-18")])

@MainActor
@Suite struct DetailStoreFranchiseTests {
    private func movie(_ tmdbID: Int) -> MediaItem {
        MediaItem(id: "movie:tmdb:\(tmdbID)", kind: .movie, title: "The Hunger Games",
                  year: 2012, sources: [], seasons: [], tmdbID: tmdbID)
    }

    @Test func loadsTheFranchiseInReleaseOrderWithAPosition() async {
        let store = DetailStore(item: movie(131634),
                                details: FranchiseDetails(ref: hungerGamesRef, collection: hungerGames),
                                watch: nil)
        await store.load()
        #expect(store.franchise?.name == "The Hunger Games Collection")
        #expect(store.franchise?.parts.map(\.id) == [70160, 101299, 131634, 131631, 695721])
        #expect(store.franchise?.position == 3)
        #expect(store.franchise?.count == 5)
    }

    @Test func anUnreleasedEntryIsNeitherShownNorCounted() async {
        let store = DetailStore(item: movie(70160),
                                details: FranchiseDetails(ref: hungerGamesRef, collection: hungerGames),
                                watch: nil)
        await store.load()
        #expect(store.franchise?.parts.contains { $0.id == 1233413 } == false)
        #expect(store.franchise?.count == 5)
    }

    @Test func noCollectionMeansNoFranchise() async {
        let store = DetailStore(item: movie(603),
                                details: FranchiseDetails(ref: nil, collection: nil), watch: nil)
        await store.load()
        #expect(store.franchise == nil)
    }

    @Test func aFailedCollectionFetchLeavesTheRestOfThePageIntact() async {
        let store = DetailStore(item: movie(70160),
                                details: FranchiseDetails(ref: hungerGamesRef, collection: nil),
                                watch: nil)
        await store.load()
        #expect(store.franchise == nil)
        #expect(store.richState == .loaded)
        #expect(store.runtime == 142)
    }

    @Test func aCollectionOfOneIsNotAFranchise() async {
        let lonely = TMDBCollection(id: 9, name: "Lonely Collection", overview: nil,
                                    posterPath: nil, backdropPath: nil,
                                    parts: [part(70160, "The Hunger Games", "2012-03-12")])
        let store = DetailStore(item: movie(70160),
                                details: FranchiseDetails(ref: hungerGamesRef, collection: lonely),
                                watch: nil)
        await store.load()
        #expect(store.franchise == nil)
    }
}
