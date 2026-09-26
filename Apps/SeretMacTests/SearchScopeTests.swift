import Testing
@testable import Seret

@Suite struct SearchScopeTests {
    @Test func scopesMapToKinds() {
        #expect(SearchScope.all.kind == nil)
        #expect(SearchScope.movies.kind == .movie)
        #expect(SearchScope.shows.kind == .show)
    }

    @Test func aRequestKeyIgnoresSurroundingSpace() {
        #expect(SearchRequestKey(query: " dune ", scope: .all) == SearchRequestKey(query: "dune", scope: .all))
    }

    @Test func aBlankQueryIsEmpty() {
        #expect(SearchRequestKey(query: "   ", scope: .all).isEmpty)
        #expect(!SearchRequestKey(query: "dune", scope: .all).isEmpty)
    }
}
