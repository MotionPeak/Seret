import Testing
@testable import DebridCore

@Suite struct LetterboxdRatingTests {
    @Test func everySeretRatingRoundTripsThroughStars() {
        for rating in 1...10 {
            let stars = LetterboxdRating.stars(fromSeret: rating)
            #expect(stars == Double(rating) / 2.0)
            #expect(LetterboxdRating.seret(fromStars: stars!) == rating)
        }
    }

    @Test func knownValuesConvertExactly() {
        #expect(LetterboxdRating.stars(fromSeret: 1) == 0.5)
        #expect(LetterboxdRating.stars(fromSeret: 7) == 3.5)
        #expect(LetterboxdRating.stars(fromSeret: 10) == 5.0)
    }

    @Test func outOfRangeIsRejectedRatherThanClamped() {
        #expect(LetterboxdRating.stars(fromSeret: 0) == nil)
        #expect(LetterboxdRating.stars(fromSeret: 11) == nil)
        #expect(LetterboxdRating.stars(fromSeret: -3) == nil)
        #expect(LetterboxdRating.seret(fromStars: 0.0) == nil)
        #expect(LetterboxdRating.seret(fromStars: 5.5) == nil)
    }

    @Test func nonHalfStepStarsAreRejected() {
        #expect(LetterboxdRating.seret(fromStars: 3.7) == nil)
        #expect(LetterboxdRating.seret(fromStars: 2.25) == nil)
    }
}
