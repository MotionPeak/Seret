import Testing
@testable import Seret

@Suite struct ScrubMathTests {
    @Test func fractionIsClampedToTheTrack() {
        #expect(ScrubMath.fraction(x: -50, width: 200) == 0)
        #expect(ScrubMath.fraction(x: 260, width: 200) == 1)
        #expect(ScrubMath.fraction(x: 50, width: 0) == 0)
    }

    @Test func timeIsFractionOfDuration() {
        #expect(ScrubMath.time(fraction: 0.5, duration: 8160) == 4080)
        #expect(ScrubMath.time(fraction: 0, duration: 8160) == 0)
        #expect(ScrubMath.time(fraction: 1, duration: 8160) == 8160)
    }

    @Test func unknownDurationSeeksNowhere() {
        #expect(ScrubMath.time(fraction: 0.5, duration: 0) == 0)
    }
}
