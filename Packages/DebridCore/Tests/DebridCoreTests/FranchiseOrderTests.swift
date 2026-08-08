import Testing
import Foundation
@testable import DebridCore

@Suite struct FranchiseOrderTests {
    /// "Today" for these tests, so "Sunrise on the Reaping" (2026-11-20) is not out yet.
    private var now: Date { ISO8601Timestamp.date(from: "2026-08-08T12:00:00Z")! }

    @Test func rendersTodayInTMDBsShape() {
        // Pins the format the whole comparison rests on: it must match a TMDB release_date exactly,
        // and it must be UTC — which side of midnight the viewer is on cannot change what is out.
        #expect(FranchiseOrder.dateString(now) == "2026-08-08")
    }

    private func movie(_ id: Int, _ title: String, _ date: String?) -> TMDBSearchResult {
        TMDBSearchResult(id: id, title: title, name: nil, releaseDate: date, firstAirDate: nil,
                         posterPath: nil, overview: nil, voteAverage: nil)
    }

    /// The real Hunger Games collection, deliberately shuffled: TMDB does not return parts in order.
    private var hungerGames: [TMDBSearchResult] {
        [movie(101299, "Catching Fire", "2013-11-15"),
         movie(695721, "The Ballad of Songbirds & Snakes", "2023-11-15"),
         movie(70160, "The Hunger Games", "2012-03-12"),
         movie(1233413, "Sunrise on the Reaping", "2026-11-20"),
         movie(131634, "Mockingjay - Part 1", "2014-11-18"),
         movie(131631, "Mockingjay - Part 2", "2015-11-18")]
    }

    @Test func ordersByReleaseDate() {
        let ordered = FranchiseOrder.ordered(hungerGames, now: now)
        #expect(ordered.map(\.id) == [70160, 101299, 131634, 131631, 695721])
    }

    @Test func aPrequelSitsWhereItWasReleased() {
        // The Ballad is a prequel but came out fifth — release order, not story order.
        let ordered = FranchiseOrder.ordered(hungerGames, now: now)
        #expect(ordered.last?.id == 695721)
    }

    @Test func dropsUnreleasedFilms() {
        let ordered = FranchiseOrder.ordered(hungerGames, now: now)
        #expect(!ordered.contains { $0.id == 1233413 })
        #expect(ordered.count == 5)
    }

    @Test func dropsEntriesWithNoReleaseDate() {
        let parts = hungerGames + [movie(999, "Untitled Sequel", nil), movie(998, "Blank", "")]
        let ordered = FranchiseOrder.ordered(parts, now: now)
        #expect(!ordered.contains { $0.id == 999 || $0.id == 998 })
    }

    @Test func dedupesByID() {
        let parts = hungerGames + [movie(70160, "The Hunger Games", "2012-03-12")]
        #expect(FranchiseOrder.ordered(parts, now: now).count == 5)
    }

    @Test func positionIsOneBased() {
        let ordered = FranchiseOrder.ordered(hungerGames, now: now)
        #expect(FranchiseOrder.position(of: 70160, in: ordered) == 1)
        #expect(FranchiseOrder.position(of: 131634, in: ordered) == 3)
        #expect(FranchiseOrder.position(of: 695721, in: ordered) == 5)
    }

    @Test func positionIsNilForAFilmNotInTheOrder() {
        let ordered = FranchiseOrder.ordered(hungerGames, now: now)
        #expect(FranchiseOrder.position(of: 1233413, in: ordered) == nil)   // unreleased, dropped
        #expect(FranchiseOrder.position(of: 42, in: ordered) == nil)
    }

    @Test func aFilmReleasedTodayCounts() {
        let today = movie(555, "Out Today", FranchiseOrder.dateString(now))
        let ordered = FranchiseOrder.ordered([today], now: now)
        #expect(ordered.map(\.id) == [555])
    }
}
