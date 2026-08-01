import Testing
import Foundation
import DebridCore
@testable import DebridUI

@Suite struct GenreSortTests {
    @Test func sortsCoverPopularNewAndTopRated() {
        #expect(GenreSort.allCases.map(\.title) == ["Popular", "New", "Top Rated"])
    }

    @Test func sortIsIdentifiedByItsTitle() {
        #expect(GenreSort.popular.id == "Popular")
    }
}

/// A one-shot latch. Lets a *stale* in-flight fetch be released after a newer one has already
/// finished — the focus-glide race in miniature.
private actor Gate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        open = true
        for w in waiters { w.resume() }
        waiters.removeAll()
    }
}

private final class FakeGenreBrowsing: GenreBrowsing, @unchecked Sendable {
    /// Fetches for this genre id block until `gate` is released.
    var gatedGenreID: Int?
    let gate = Gate()
    var failEverything = false
    var emptyEverything = false
    /// Pages beyond this come back empty, so end-of-results can be exercised.
    var lastNonEmptyPage = Int.max

    private let lock = NSLock()
    private var _calls: [(genreID: Int, sort: GenreSort, page: Int)] = []
    var calls: [(genreID: Int, sort: GenreSort, page: Int)] { lock.withLock { _calls } }

    func titles(kind: MediaKind, genreID: Int,
                sort: GenreSort, page: Int) async throws -> [TMDBSearchResult] {
        lock.withLock { _calls.append((genreID, sort, page)) }
        if genreID == gatedGenreID { await gate.wait() }
        if failEverything { throw URLError(.badServerResponse) }
        if emptyEverything || page > lastNonEmptyPage { return [] }
        // Ids encode genre + sort + page, so assertions can prove *which* fetch landed.
        let sortIndex = GenreSort.allCases.firstIndex(of: sort) ?? 0
        let base = genreID * 1_000 + sortIndex * 100 + page * 10
        return (0..<3).map { result(base + $0) }
    }
}

private func result(_ id: Int) -> TMDBSearchResult {
    TMDBSearchResult(id: id, title: "M\(id)", name: nil, releaseDate: "2024-01-01",
                     firstAirDate: nil, posterPath: "/p.jpg", overview: nil, voteAverage: 7)
}

private let action = DiscoverStore.Genre(name: "Action", tmdbID: 28)
private let comedy = DiscoverStore.Genre(name: "Comedy", tmdbID: 35)

@MainActor
@Suite struct GenreGridStoreTests {
    private func store(_ fake: FakeGenreBrowsing,
                       genre: DiscoverStore.Genre = action) -> GenreGridStore {
        GenreGridStore(kind: .movie, genre: genre, browsing: fake)
    }

    @Test func loadPopulatesHitsAndFlipsToLoaded() async {
        let fake = FakeGenreBrowsing()
        let s = store(fake)
        await s.load()
        #expect(s.state == .loaded)
        #expect(s.hits.count == 3)
        #expect(fake.calls.first?.genreID == 28)
        #expect(fake.calls.first?.page == 1)
    }

    @Test func emptyFirstPageIsFailedNotLoaded() async {
        let fake = FakeGenreBrowsing()
        fake.emptyEverything = true
        let s = store(fake)
        await s.load()
        #expect(s.state == .failed)
        #expect(s.hits.isEmpty)
    }

    @Test func throwingFirstPageIsFailed() async {
        let fake = FakeGenreBrowsing()
        fake.failEverything = true
        let s = store(fake)
        await s.load()
        #expect(s.state == .failed)
    }

    @Test func changingSortRefetchesFromPageOne() async {
        let fake = FakeGenreBrowsing()
        let s = store(fake)
        await s.load()
        let firstBatch = s.hits
        await s.select(sort: .topRated)
        #expect(s.sort == .topRated)
        #expect(s.hits != firstBatch)
        #expect(fake.calls.last?.sort == .topRated)
        #expect(fake.calls.last?.page == 1)
    }

    @Test func loadMoreAppendsTheNextPageAndDedupes() async {
        let fake = FakeGenreBrowsing()
        let s = store(fake)
        await s.load()
        let firstPage = s.hits
        await s.loadMore()
        #expect(s.hits.count == 6)
        #expect(Array(s.hits.prefix(3)) == firstPage)           // page 1 stays put
        #expect(Set(s.hits.map(\.id)).count == s.hits.count)     // no duplicate ids
        #expect(fake.calls.last?.page == 2)
    }

    @Test func loadMoreStopsAtTheEndOfResults() async {
        let fake = FakeGenreBrowsing()
        fake.lastNonEmptyPage = 1
        let s = store(fake)
        await s.load()
        await s.loadMore()
        #expect(s.reachedEnd)
        #expect(s.hits.count == 3)
        let callsAfterEnd = fake.calls.count
        await s.loadMore()                                      // must not fire another request
        #expect(fake.calls.count == callsAfterEnd)
    }

    /// The focus-glide race: a gated fetch for Action is still in flight when the user lands on
    /// Comedy. Releasing Action afterwards must NOT overwrite Comedy's grid.
    @Test func staleGenreFetchIsDiscarded() async {
        let fake = FakeGenreBrowsing()
        fake.gatedGenreID = 28
        let s = store(fake)

        async let stale: Void = s.load()                        // Action — blocks on the gate
        await Task.yield()
        await s.select(genre: comedy)
        let comedyHits = s.hits
        #expect(!comedyHits.isEmpty)

        await fake.gate.release()
        _ = await stale

        #expect(s.genre.tmdbID == 35)
        #expect(s.hits == comedyHits)                           // Action's results never landed
        #expect(s.state == .loaded)
    }

    /// Same race one level down: a gated page-2 append must not land after the genre changed.
    @Test func staleLoadMoreIsDiscarded() async {
        let fake = FakeGenreBrowsing()
        let s = store(fake)
        await s.load()
        fake.gatedGenreID = 28                                  // gate only the *next* Action call

        async let stale: Void = s.loadMore()
        await Task.yield()
        await s.select(genre: comedy)
        let comedyHits = s.hits

        await fake.gate.release()
        _ = await stale

        #expect(s.hits == comedyHits)
    }
}
