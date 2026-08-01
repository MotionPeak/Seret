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
