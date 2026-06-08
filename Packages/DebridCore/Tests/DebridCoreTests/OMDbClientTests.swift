import Testing
import Foundation
@testable import DebridCore

struct OMDbRatingsValueTests {
    @Test func hasAnyTrueWithAnyScore() {
        #expect(OMDbRatings(imdb: 8.7, rottenTomatoes: nil, metacritic: nil).hasAny)
        #expect(OMDbRatings(imdb: nil, rottenTomatoes: 88, metacritic: nil).hasAny)
        #expect(OMDbRatings(imdb: nil, rottenTomatoes: nil, metacritic: 73).hasAny)
    }

    @Test func hasAnyFalseWhenAllNil() {
        #expect(!OMDbRatings(imdb: nil, rottenTomatoes: nil, metacritic: nil).hasAny)
    }
}
