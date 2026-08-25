import Testing
import Foundation
@testable import DebridCore

@Suite struct ETAEstimatorTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    /// One sample says nothing about a rate, and with no reported speed there is nothing to fall
    /// back on. Guessing here is what produces a wrong number on the very first frame the user sees.
    @Test func singleSampleWithoutReportedSpeedGivesNoEstimate() {
        var e = ETAEstimator()
        #expect(e.observe(fraction: 0, totalBytes: 1000, reportedSpeed: nil, at: at(0)) == nil)
    }

    @Test func firstSampleFallsBackToReportedSpeed() {
        var e = ETAEstimator()
        // 1000 bytes total, none done, RD says 100 B/s -> 10s.
        let eta = e.observe(fraction: 0, totalBytes: 1000, reportedSpeed: 100, at: at(0))
        #expect(eta == 10.0)
    }

    @Test func steadyRateGivesTheExactRemainingTime() {
        var e = ETAEstimator()
        _ = e.observe(fraction: 0, totalBytes: 1000, reportedSpeed: nil, at: at(0))
        // 500 bytes in 10s = 50 B/s; 500 bytes remain -> 10s.
        let eta = e.observe(fraction: 0.5, totalBytes: 1000, reportedSpeed: nil, at: at(10))
        #expect(eta == 10.0)
    }

    /// A 4x speed spike must not yank the ETA down to the spike's implied value.
    @Test func aSpikeIsSmoothedRatherThanFollowed() {
        var e = ETAEstimator()
        let total = 10_000_000
        _ = e.observe(fraction: 0, totalBytes: total, reportedSpeed: nil, at: at(0))
        _ = e.observe(fraction: 0.1, totalBytes: total, reportedSpeed: nil, at: at(10))  // 100 kB/s
        // 4 MB in the next 10s = 400 kB/s. Raw would give 5 MB / 400 kB/s = 12.5s.
        let eta = e.observe(fraction: 0.5, totalBytes: total, reportedSpeed: nil, at: at(20))
        let smoothedRate = 0.3 * 400_000 + 0.7 * 100_000   // 190 kB/s
        #expect(abs(eta! - 5_000_000 / smoothedRate) < 0.01)
        #expect(eta! > 20)   // did not snap to the 12.5s the spike alone implies
    }

    @Test func aStalledDownloadGivesNoEstimate() {
        var e = ETAEstimator()
        #expect(e.observe(fraction: 0.3, totalBytes: 1000, reportedSpeed: 0, at: at(0)) == nil)
        // Progress unchanged 10s later, RD still reports zero.
        #expect(e.observe(fraction: 0.3, totalBytes: 1000, reportedSpeed: 0, at: at(10)) == nil)
    }

    /// The app was backgrounded for 10 minutes. Averaging across that dead time would report a
    /// throughput of ~0.17 B/s and an ETA of ~40 minutes for 400 bytes. Refuse instead.
    @Test func aLongGapDiscardsStaleSamples() {
        var e = ETAEstimator()
        _ = e.observe(fraction: 0, totalBytes: 1000, reportedSpeed: nil, at: at(0))
        #expect(e.observe(fraction: 0.5, totalBytes: 1000, reportedSpeed: nil, at: at(10)) == 10.0)
        let eta = e.observe(fraction: 0.6, totalBytes: 1000, reportedSpeed: nil, at: at(600))
        #expect(eta == nil)
    }

    @Test func aCompletedDownloadHasNoTimeRemaining() {
        var e = ETAEstimator()
        _ = e.observe(fraction: 0, totalBytes: 1000, reportedSpeed: 100, at: at(0))
        #expect(e.observe(fraction: 1.0, totalBytes: 1000, reportedSpeed: 100, at: at(10)) == 0)
    }

    /// Two polls landing in the same second must not replace the anchor sample — otherwise the
    /// measured interval collapses toward zero and the computed rate explodes.
    @Test func samplesCloserThanTheMinimumIntervalDoNotResetTheAnchor() {
        var e = ETAEstimator(minInterval: 1)
        _ = e.observe(fraction: 0, totalBytes: 1000, reportedSpeed: nil, at: at(0))
        _ = e.observe(fraction: 0.01, totalBytes: 1000, reportedSpeed: nil, at: at(0.2))
        // Anchor is still t0, so this measures 500 bytes over the full 10s = 50 B/s -> 10s.
        #expect(e.observe(fraction: 0.5, totalBytes: 1000, reportedSpeed: nil, at: at(10)) == 10.0)
    }

    /// A zero-byte torrent has nothing left to fetch, so it reads as complete rather than unknown.
    @Test func zeroTotalBytesIsAlreadyComplete() {
        var e = ETAEstimator()
        #expect(e.observe(fraction: 0, totalBytes: 0, reportedSpeed: 100, at: at(0)) == 0)
    }

    /// A zero observation was thrown away rather than averaged in, so the last rate that HAPPENED
    /// to be positive lived on forever. A download that stopped moving therefore kept showing a
    /// confident, steadily-counting-down ETA -- the exact "inventing a number when it cannot know"
    /// this type says it will not do.
    @Test func aStalledDownloadStopsClaimingToKnowWhenItWillFinish() {
        var e = ETAEstimator()
        _ = e.observe(fraction: 0, totalBytes: 10_000, reportedSpeed: nil, at: at(0))
        let moving = e.observe(fraction: 0.5, totalBytes: 10_000, reportedSpeed: nil, at: at(10))
        #expect(moving == 10.0)           // 500 B/s, 5000 bytes left

        // Now nothing moves. Poll every 10s, as the monitor does.
        var last: TimeInterval??
        for step in stride(from: 20.0, through: 120.0, by: 10.0) {
            last = e.observe(fraction: 0.5, totalBytes: 10_000, reportedSpeed: nil, at: at(step))
        }
        #expect(last ?? nil == nil)
    }

    /// A flat poll HOLDS the estimate rather than moving it.
    ///
    /// This used to assert the estimate grew, on the reasoning that a stall should read as slowing
    /// down before it gives up. That reasoning was wrong for the shape of the data: RD reports
    /// progress in whole percent, so most polls of a large download are flat while bytes are moving
    /// the whole time — and treating each of those as a slowdown decayed the rate toward nothing
    /// and drove the estimate into the hundreds of hours before it snapped back at the next step.
    /// A flat poll now says nothing at all, and a sustained one is caught by the stall rule.
    @Test func aFlatPollHoldsTheEstimateSteady() {
        var e = ETAEstimator()
        _ = e.observe(fraction: 0, totalBytes: 10_000, reportedSpeed: nil, at: at(0))
        let moving = e.observe(fraction: 0.5, totalBytes: 10_000, reportedSpeed: nil, at: at(10))
        let firstFlat = e.observe(fraction: 0.5, totalBytes: 10_000, reportedSpeed: nil, at: at(20))
        #expect(moving == 10.0)
        #expect(firstFlat == moving)
    }

    /// A stall that RECOVERS must report again, not stay dark.
    @Test func aRecoveredDownloadEstimatesAgain() {
        var e = ETAEstimator()
        _ = e.observe(fraction: 0, totalBytes: 10_000, reportedSpeed: nil, at: at(0))
        _ = e.observe(fraction: 0.5, totalBytes: 10_000, reportedSpeed: nil, at: at(10))
        for step in stride(from: 20.0, through: 120.0, by: 10.0) {
            _ = e.observe(fraction: 0.5, totalBytes: 10_000, reportedSpeed: nil, at: at(step))
        }
        let resumed = e.observe(fraction: 0.75, totalBytes: 10_000, reportedSpeed: nil, at: at(130))
        #expect(resumed != nil)
    }

    /// A download that has not started yet is not a stall — there is simply nothing to measure, and
    /// RD's reported speed remains the only signal.
    @Test func aDownloadThatHasNotMovedYetStillUsesTheReportedSpeed() {
        var e = ETAEstimator()
        _ = e.observe(fraction: 0, totalBytes: 10_000, reportedSpeed: 100, at: at(0))
        let eta = e.observe(fraction: 0, totalBytes: 10_000, reportedSpeed: 100, at: at(10))
        #expect(eta == 100.0)
    }

    /// RD reports `progress` as a percentage, so on a large slow download a single reported step
    /// can take minutes while bytes are moving the whole time. Calling that a stall blanked the ETA
    /// of a download that was working perfectly well. A live reported speed says it is not stalled.
    @Test func aSlowButMovingDownloadStillEstimates() {
        var e = ETAEstimator()
        _ = e.observe(fraction: 0, totalBytes: 10_000, reportedSpeed: 50, at: at(0))
        _ = e.observe(fraction: 0.5, totalBytes: 10_000, reportedSpeed: 50, at: at(10))
        var last: TimeInterval??
        for step in stride(from: 20.0, through: 200.0, by: 10.0) {
            last = e.observe(fraction: 0.5, totalBytes: 10_000, reportedSpeed: 50, at: at(step))
        }
        #expect((last ?? nil) != nil)
    }

    /// …and one RD reports NO speed for, with nothing moving, still gives up.
    @Test func aStallWithNoReportedSpeedStillGivesUp() {
        var e = ETAEstimator()
        _ = e.observe(fraction: 0, totalBytes: 10_000, reportedSpeed: nil, at: at(0))
        _ = e.observe(fraction: 0.5, totalBytes: 10_000, reportedSpeed: nil, at: at(10))
        var last: TimeInterval??
        for step in stride(from: 20.0, through: 200.0, by: 10.0) {
            last = e.observe(fraction: 0.5, totalBytes: 10_000, reportedSpeed: 0, at: at(step))
        }
        #expect((last ?? nil) == nil)
    }

    /// RD reports progress in whole percent, so a large download's byte count jumps once every
    /// couple of minutes while bytes move throughout. Folding the zeros between steps into the
    /// smoothed rate decayed it toward nothing: the estimate climbed to absurdity and then snapped
    /// back at the next step. Measuring across the whole flat window gives the TRUE average rate.
    @Test func aCoarselyReportedDownloadHoldsASteadyEstimate() {
        var e = ETAEstimator()
        // 1000 bytes total. Progress steps 10% every 100s; polled every 10s.
        _ = e.observe(fraction: 0, totalBytes: 1000, reportedSpeed: 1, at: at(0))
        var estimates: [TimeInterval] = []
        var fraction = 0.0
        for tick in stride(from: 10.0, through: 400.0, by: 10.0) {
            if Int(tick) % 100 == 0 { fraction += 0.1 }
            if let eta = e.observe(fraction: fraction, totalBytes: 1000, reportedSpeed: 1, at: at(tick)) {
                estimates.append(eta)
            }
        }
        // The true rate is 1 byte/s and `remaining` runs 900 → 600, so every estimate should sit
        // near those numbers. What the decay produced instead was a sawtooth: correct at each step,
        // then climbing by orders of magnitude across the flat stretch before snapping back — so
        // the assertion that matters is on the SPREAD, not the ceiling.
        let low = estimates.min() ?? 0, high = estimates.max() ?? 0
        #expect(low > 100)
        #expect(high < 2_000)
        #expect(high / max(low, 1) < 5)      // the sawtooth spanned four orders of magnitude
    }

    /// RD queues a torrent before it starts moving bytes. The anchor only advances on real
    /// movement, so one planted during the queue stays there — and the first measured rate then
    /// spans the wait as if it were transfer time, reading an order of magnitude slow.
    @Test func timeSpentQueuedDoesNotDiluteTheFirstMeasuredRate() {
        var e = ETAEstimator()
        // Three minutes queued: polled, but nothing downloaded.
        for tick in stride(from: 0.0, through: 180.0, by: 10.0) {
            _ = e.observe(fraction: 0, totalBytes: 10_000, reportedSpeed: nil, at: at(tick))
        }
        // Then it moves: 1000 bytes in 10s = 100 B/s, so 9000 remaining ≈ 90s.
        let eta = e.observe(fraction: 0.1, totalBytes: 10_000, reportedSpeed: nil, at: at(190))
        #expect(eta != nil)
        #expect((eta ?? 0) < 200)      // diluted by the queue it would have been ~1700
    }
}
