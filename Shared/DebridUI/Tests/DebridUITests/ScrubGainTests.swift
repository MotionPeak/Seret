import Testing
import Foundation
@testable import DebridUI

@Suite struct ScrubGainTests {
    private let twoHours: Double = 7200

    @Test func noDisplacementIsNoMovement() {
        #expect(ScrubGain.seconds(forDisplacement: 0, duration: twoHours) == 0)
    }

    @Test func directionIsPreserved() {
        let forward = ScrubGain.seconds(forDisplacement: 200, duration: twoHours)
        let back = ScrubGain.seconds(forDisplacement: -200, duration: twoHours)
        #expect(forward > 0)
        #expect(back == -forward)
    }

    @Test func smallMovesAreFineGrained() {
        // 5% of half the surface must stay in single-digit seconds — precise enough to land on a
        // line of dialogue on a 2-hour film.
        let d = ScrubGain.seconds(forDisplacement: ScrubGain.halfSurface * 0.05, duration: twoHours)
        #expect(d > 0)
        #expect(d < 10)
    }

    /// The reported "skips too much" lived here — not at the extremes, which were always fine, but
    /// in the middle of the surface where ordinary aiming happens. A fifth of the reachable travel
    /// must stay inside a shot, not throw you most of a minute.
    @Test func midRangeMovesStayUsable() {
        let fifth = ScrubGain.seconds(forDisplacement: ScrubGain.halfSurface * 0.2, duration: twoHours)
        let third = ScrubGain.seconds(forDisplacement: ScrubGain.halfSurface * 0.3, duration: twoHours)
        #expect(fifth < 20, "was 40s with a cubic ramp")
        #expect(third < 40, "was 114s with a cubic ramp")
    }

    @Test func aFullSweepCoversHalfTheFilm() {
        let d = ScrubGain.seconds(forDisplacement: ScrubGain.halfSurface, duration: twoHours)
        #expect(abs(d - twoHours / 2) < 1)
    }

    @Test func displacementIsClampedToTheSurface() {
        let atEdge = ScrubGain.seconds(forDisplacement: ScrubGain.halfSurface, duration: twoHours)
        let beyond = ScrubGain.seconds(forDisplacement: ScrubGain.halfSurface * 4, duration: twoHours)
        #expect(beyond == atEdge)
    }

    @Test func theCurveIsMonotonic() {
        var previous = -Double.infinity
        for points in stride(from: 0.0, through: ScrubGain.halfSurface, by: 20) {
            let d = ScrubGain.seconds(forDisplacement: points, duration: twoHours)
            #expect(d >= previous)
            previous = d
        }
    }

    @Test func anUnknownDurationStillMovesTheHandle() {
        // Duration is 0 until the media reports it; scrubbing must not divide by zero or freeze.
        let d = ScrubGain.seconds(forDisplacement: ScrubGain.halfSurface * 0.5, duration: 0)
        #expect(d > 0)
    }

    @Test func aShortClipNeverOvershootsItsOwnLength() {
        let d = ScrubGain.seconds(forDisplacement: ScrubGain.halfSurface, duration: 60)
        #expect(abs(d - 30) < 1)
    }
}
