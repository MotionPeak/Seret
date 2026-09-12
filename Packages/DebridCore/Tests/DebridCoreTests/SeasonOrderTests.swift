import Testing
import Foundation
@testable import DebridCore

/// Specials sort LAST. Sorted naively, season 0 comes first and a show opens on its unaired pilot —
/// the same fault that filing that pilot as S1E0 caused, just moved one step along.
@Suite struct SeasonOrderTests {

    @Test func specialsComeAfterEveryRealSeason() {
        #expect([2, 0, 1, 4, 3].sortedBySeason() == [1, 2, 3, 4, 0])
    }

    @Test func realSeasonsKeepTheirOrder() {
        #expect([3, 1, 2].sortedBySeason() == [1, 2, 3])
    }

    @Test func aShowWithOnlySpecialsStillOrders() {
        #expect([0].sortedBySeason() == [0])
    }

    @Test func seasonValuesOrderTheSameWay() {
        let seasons = [Season(number: 0, episodes: []), Season(number: 2, episodes: []),
                       Season(number: 1, episodes: [])]
        #expect(seasons.sortedBySeason().map(\.number) == [1, 2, 0])
    }

    @Test func specialsAreNamedRatherThanNumbered() {
        #expect(SeasonOrder.label(0) == "Specials")
        #expect(SeasonOrder.label(1) == "Season 1")
        #expect(SeasonOrder.label(12) == "Season 12")
    }
}
