import Testing
import Foundation
@testable import DebridUI

/// Deciding when the system Now Playing entry actually needs rewriting.
///
/// `PlayerModel.tick()` calls `pushNowPlaying()` on every VLCKit time event — several times a
/// second. Each push is a cross-process write that re-encodes the poster JPEG, so pushing every
/// tick is pure waste. The system extrapolates the playhead from elapsed-time + rate, so it only
/// needs telling when that extrapolation would be WRONG.
///
/// (`#expect` cannot call a `mutating` method inline — it captures the value immutably — so every
/// decision is taken into a local first.)
struct NowPlayingThrottleTests {

    private let identity = "Blade Runner|nil|6000"

    @Test func theFirstUpdateAlwaysPushes() {
        var throttle = NowPlayingThrottle()
        let pushed = throttle.shouldPush(identity: identity, position: 0, rate: 1, now: 0)
        #expect(pushed)
    }

    @Test func steadyPlaybackDoesNotPushEveryTick() {
        var throttle = NowPlayingThrottle()
        _ = throttle.shouldPush(identity: identity, position: 0, rate: 1, now: 0)
        // Four ticks a second, all exactly where the system already predicts the playhead to be.
        for step in 1...8 {
            let t = Double(step) * 0.25
            let pushed = throttle.shouldPush(identity: identity, position: t, rate: 1, now: t)
            #expect(pushed == false)
        }
    }

    @Test func aSeekPushesImmediately() {
        var throttle = NowPlayingThrottle()
        _ = throttle.shouldPush(identity: identity, position: 0, rate: 1, now: 0)
        // One second later the playhead is at 40s, not 1s — the extrapolation is now wrong.
        let pushed = throttle.shouldPush(identity: identity, position: 40, rate: 1, now: 1)
        #expect(pushed)
    }

    @Test func pausingAndResumingPush() {
        var throttle = NowPlayingThrottle()
        _ = throttle.shouldPush(identity: identity, position: 0, rate: 1, now: 0)
        let paused = throttle.shouldPush(identity: identity, position: 1, rate: 0, now: 1)
        let resumed = throttle.shouldPush(identity: identity, position: 1, rate: 1, now: 2)
        #expect(paused)
        #expect(resumed)
    }

    @Test func aNewTitlePushes() {
        var throttle = NowPlayingThrottle()
        _ = throttle.shouldPush(identity: identity, position: 0, rate: 1, now: 0)
        let pushed = throttle.shouldPush(identity: "Dune|nil|9000", position: 0, rate: 1, now: 0.25)
        #expect(pushed)
    }

    /// A slow heartbeat still refreshes the entry, so the system can never drift far even if our
    /// own clock and VLCKit's disagree slightly.
    @Test func aHeartbeatStillRefreshesPeriodically() {
        var throttle = NowPlayingThrottle(heartbeat: 5, tolerance: 2)
        _ = throttle.shouldPush(identity: identity, position: 0, rate: 1, now: 0)
        let early = throttle.shouldPush(identity: identity, position: 4, rate: 1, now: 4)
        let due = throttle.shouldPush(identity: identity, position: 5, rate: 1, now: 5)
        #expect(early == false)
        #expect(due)
    }

    /// Drift is measured from the last PUSHED state, not the last observed one — otherwise a slow
    /// creep would never accumulate past the tolerance and a real desync would go unreported.
    @Test func driftIsMeasuredFromTheLastPush() {
        var throttle = NowPlayingThrottle(heartbeat: 100, tolerance: 2)
        _ = throttle.shouldPush(identity: identity, position: 0, rate: 1, now: 0)
        // Each tick slips 0.5s further behind where the system predicts it.
        let first = throttle.shouldPush(identity: identity, position: 0.5, rate: 1, now: 1)
        let second = throttle.shouldPush(identity: identity, position: 1.0, rate: 1, now: 2)
        let third = throttle.shouldPush(identity: identity, position: 1.5, rate: 1, now: 4)
        #expect(first == false)
        #expect(second == false)
        #expect(third)          // 2.5s behind the prediction — past the tolerance
    }

    /// While paused the predicted playhead does not move, so a scrub while paused must still push.
    @Test func scrubbingWhilePausedPushes() {
        var throttle = NowPlayingThrottle()
        _ = throttle.shouldPush(identity: identity, position: 100, rate: 0, now: 0)
        let idle = throttle.shouldPush(identity: identity, position: 100.1, rate: 0, now: 1)
        let scrubbed = throttle.shouldPush(identity: identity, position: 300, rate: 0, now: 2)
        #expect(idle == false)
        #expect(scrubbed)
    }

    @Test func resetMakesTheNextUpdatePushAgain() {
        var throttle = NowPlayingThrottle()
        _ = throttle.shouldPush(identity: identity, position: 0, rate: 1, now: 0)
        let quiet = throttle.shouldPush(identity: identity, position: 0.25, rate: 1, now: 0.25)
        throttle.reset()
        let afterReset = throttle.shouldPush(identity: identity, position: 0.5, rate: 1, now: 0.5)
        #expect(quiet == false)
        #expect(afterReset)
    }
}
