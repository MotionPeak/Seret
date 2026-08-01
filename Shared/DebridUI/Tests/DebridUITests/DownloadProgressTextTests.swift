import Testing
import Foundation
import DebridCore
@testable import DebridUI

@Suite struct DownloadProgressTextTests {
    private func downloading(_ fraction: Double, eta: TimeInterval?, seeders: Int? = 5)
        -> DownloadStatus {
        DownloadStatus(torrentID: "T", contentKey: "movie:tmdb:1", tmdbID: 1,
                       phase: .downloading, fraction: fraction, bytesTotal: 1000,
                       seeders: seeders, secondsRemaining: eta)
    }

    @Test func percentIsWholeNumbers() {
        #expect(DownloadProgressText.percent(0.6449) == "64%")
        #expect(DownloadProgressText.percent(0) == "0%")
        #expect(DownloadProgressText.percent(1) == "100%")
    }

    @Test func anUnknownRemainingTimeHasNoText() {
        #expect(DownloadProgressText.remaining(nil) == nil)
    }

    /// Seconds would twitch on every poll, and the download is nearly done anyway.
    @Test func underNinetySecondsReadsAsLessThanAMinute() {
        #expect(DownloadProgressText.remaining(5) == "less than a minute left")
        #expect(DownloadProgressText.remaining(89) == "less than a minute left")
    }

    @Test func minutesAreRoundedNotTruncated() {
        #expect(DownloadProgressText.remaining(90) == "2 min left")     // 1.5 -> 2
        #expect(DownloadProgressText.remaining(720) == "12 min left")
        #expect(DownloadProgressText.remaining(3540) == "59 min left")
    }

    @Test func hoursReadAsHoursAndMinutes() {
        #expect(DownloadProgressText.remaining(3600) == "1 hr left")
        #expect(DownloadProgressText.remaining(3840) == "1 hr 4 min left")
        #expect(DownloadProgressText.remaining(7200) == "2 hr left")
    }

    @Test func aDownloadingLineJoinsPercentAndRemaining() {
        #expect(DownloadProgressText.line(for: downloading(0.64, eta: 720))
                == "64% · 12 min left")
    }

    /// Never invent a time. The estimator returns nil when it cannot know.
    @Test func aDownloadingLineWithNoEstimateShowsOnlyPercent() {
        #expect(DownloadProgressText.line(for: downloading(0.64, eta: nil)) == "64%")
    }

    /// Zero seeders is why there is no estimate — say so instead of leaving it bare.
    @Test func noSeedersIsCalledOut() {
        #expect(DownloadProgressText.line(for: downloading(0.1, eta: nil, seeders: 0))
                == "10% · no seeders")
    }

    @Test func queuedReadsAsStarting() {
        let s = DownloadStatus(torrentID: "T", tmdbID: 1, phase: .queued, fraction: 0)
        #expect(DownloadProgressText.line(for: s) == "Starting…")
    }

    @Test func readyAndFailedSpeakForThemselves() {
        let ready = DownloadStatus(torrentID: "T", tmdbID: 1, phase: .ready, fraction: 1)
        #expect(DownloadProgressText.line(for: ready) == "Ready")
        let failed = DownloadStatus(torrentID: "T", tmdbID: 1, phase: .failed("dead"), fraction: 0)
        #expect(DownloadProgressText.line(for: failed) == "Couldn't download")
    }
}
