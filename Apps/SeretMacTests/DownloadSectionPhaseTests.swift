import DebridCore
import DebridUI
import Testing
@testable import Seret

@Suite struct DownloadSectionPhaseTests {
    private func status(_ phase: DownloadStatus.Phase, fraction: Double = 0) -> DownloadStatus {
        DownloadStatus(torrentID: "t1", contentKey: "movie:tmdb:1", tmdbID: 1, phase: phase, fraction: fraction)
    }

    @Test func nothingRequestedIsIdle() {
        #expect(DownloadSectionPhase.derive(requesting: false, status: nil) == .idle)
    }

    @Test func aRequestInFlightIsStarting() {
        #expect(DownloadSectionPhase.derive(requesting: true, status: nil) == .starting)
    }

    @Test func queuedIsStarting() {
        #expect(DownloadSectionPhase.derive(requesting: false, status: status(.queued)) == .starting)
    }

    @Test func downloadingCarriesItsFractionAndLine() {
        let s = status(.downloading, fraction: 0.42)
        #expect(DownloadSectionPhase.derive(requesting: false, status: s)
            == .downloading(fraction: 0.42, line: DownloadProgressText.line(for: s)))
    }

    @Test func aFailureCarriesItsReason() {
        #expect(DownloadSectionPhase.derive(requesting: false, status: status(.failed("no seeders")))
            == .failed("no seeders"))
    }

    @Test func readyIsIdle() {
        // About to leave the store as the library refreshes and the page upgrades in place.
        #expect(DownloadSectionPhase.derive(requesting: false, status: status(.ready)) == .idle)
    }
}
