import Testing
import Foundation
@testable import DebridUI

/// The feel of the Siri Remote scrub, pinned numerically.
///
/// Every case here drives the public mapping with LITERAL point values rather than multiples of a
/// constant, so the suite is meaningful against any parameterisation — including the previous one,
/// which it was written to falsify.
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
        // A short nudge must stay inside a shot — precise enough to land on a line of dialogue.
        let d = ScrubGain.seconds(forDisplacement: 100, duration: twoHours)
        #expect(d > 0)
        #expect(d < 8, "100pt was 6.6s; the linear term alone should own this range")
    }

    /// The reported "sensitivity is way too high" lives in the middle of the pad, where aiming
    /// actually happens. The old curve detonated here: a fifth of a sweep threw 70s and a full
    /// half-sweep threw thirty minutes.
    @Test func midRangeMovesStayUsable() {
        let quarter = ScrubGain.seconds(forDisplacement: 250, duration: twoHours)
        let half = ScrubGain.seconds(forDisplacement: 500, duration: twoHours)
        #expect(quarter < 30, "was 70s")
        #expect(half < 150, "was 1800s — half a thumb sweep threw away half an hour")
    }

    /// THE regression test for "it cuts off and doesn't let me do more than that".
    ///
    /// The old mapping clamped displacement at 500pt, so the whole outer half of the remote's
    /// travel was dead. Movement past that point must still move the marker, and keep moving it.
    @Test func travelPastTheOldClampKeepsMoving() {
        let atOldClamp = ScrubGain.seconds(forDisplacement: 500, duration: twoHours)
        let beyond = ScrubGain.seconds(forDisplacement: 700, duration: twoHours)
        let farBeyond = ScrubGain.seconds(forDisplacement: 900, duration: twoHours)
        let further = ScrubGain.seconds(forDisplacement: 1200, duration: twoHours)
        #expect(beyond > atOldClamp)
        #expect(farBeyond > beyond)
        #expect(further > farBeyond)
    }

    /// A full sweep of the pad reaches about four minutes: precision-first, because long-distance
    /// travel has its own affordance (hold left/right to scan).
    @Test func aFullSweepReachesAboutFourMinutes() {
        let d = ScrubGain.seconds(forDisplacement: ScrubGain.reach, duration: twoHours)
        #expect(abs(d - 268) < 5, "designed 4:28 at full pad travel")
    }

    /// Past the nominal reach the curve continues at its terminal SLOPE, not as a cubic. Continuing
    /// the cubic would explode — twice the reach would jump half an hour, which is the original
    /// complaint reintroduced at the far end.
    @Test func travelPastReachGrowsLinearlyNotCubically() {
        let atReach = ScrubGain.seconds(forDisplacement: ScrubGain.reach, duration: twoHours)
        let doubled = ScrubGain.seconds(forDisplacement: ScrubGain.reach * 2, duration: twoHours)
        // A continued cubic would be ~8x the coarse term here; the linear continuation is ~4x.
        #expect(doubled < atReach * 5)
        #expect(doubled > atReach * 2)
    }

    /// No seam to feel where the two segments join.
    @Test func theSegmentJoinIsContinuous() {
        let just = ScrubGain.seconds(forDisplacement: ScrubGain.reach - 0.5, duration: twoHours)
        let past = ScrubGain.seconds(forDisplacement: ScrubGain.reach + 0.5, duration: twoHours)
        #expect(abs(past - just) < 2)
    }

    /// Identical thumb movement must mean the same number of seconds on a 22-minute episode and a
    /// 3-hour film. The old mapping scaled reach with duration, so the viewer could never build a
    /// reflex — the same gesture meant wildly different things per title.
    @Test func feelDoesNotDependOnHowLongTheFilmIs() {
        for points in [100.0, 250.0, 500.0, 900.0] {
            let episode = ScrubGain.seconds(forDisplacement: points, duration: 22 * 60)
            let epic = ScrubGain.seconds(forDisplacement: points, duration: 3 * 3600)
            #expect(abs(episode - epic) < 0.001, "\(points)pt differed between title lengths")
        }
    }

    @Test func theCurveIsMonotonic() {
        var previous = -Double.infinity
        for points in stride(from: 0.0, through: 1600, by: 20) {
            let d = ScrubGain.seconds(forDisplacement: points, duration: twoHours)
            #expect(d >= previous)
            previous = d
        }
    }

    @Test func anUnknownDurationStillMovesTheHandle() {
        // Duration is 0 until the media reports it; scrubbing must not divide by zero or freeze.
        let d = ScrubGain.seconds(forDisplacement: 350, duration: 0)
        #expect(d > 0)
    }

    /// The one place duration still matters: a short clip can't be thrown four minutes.
    @Test func aShortClipNeverOvershootsItsOwnLength() {
        let d = ScrubGain.seconds(forDisplacement: ScrubGain.reach, duration: 60)
        #expect(abs(d - 30) < 1)
    }
}
