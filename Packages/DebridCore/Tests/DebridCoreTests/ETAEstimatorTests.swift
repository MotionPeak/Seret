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
}
