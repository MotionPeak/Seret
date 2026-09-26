import DebridCore
import Testing
@testable import DebridUI
@testable import Seret

@Suite struct DownloadsSummaryTests {
    private func tile(_ title: String, fraction: Double, remaining: TimeInterval? = nil,
                      seeders: Int? = 5) -> DownloadTile {
        let status = DownloadStatus(torrentID: title, contentKey: "movie:tmdb:\(title.hashValue)",
                                    tmdbID: 1, phase: .downloading, fraction: fraction,
                                    seeders: seeders, secondsRemaining: remaining, title: title)
        return DownloadTile(tmdbID: 1, title: title, posterPath: nil, status: status)
    }

    @Test func nothingDownloadingIsEmpty() {
        let summary = DownloadsSummary(tiles: [])
        #expect(summary.count == 0)
        #expect(summary.lead == nil)
        #expect(summary.leadLine == nil)
    }

    @Test func theLeadIsTheOneNearestDone() {
        let summary = DownloadsSummary(tiles: [tile("A", fraction: 0.2), tile("B", fraction: 0.8)])
        #expect(summary.lead?.title == "B")
    }

    @Test func theRingIsTheMeanProgress() {
        let summary = DownloadsSummary(tiles: [tile("A", fraction: 0.64), tile("B", fraction: 0.22)])
        #expect(abs(summary.fraction - 0.43) < 0.001)
    }

    @Test func theLeadLineUsesTheSharedProgressText() {
        let queuedStatus = DownloadStatus(torrentID: "t", contentKey: "movie:tmdb:1", tmdbID: 1,
                                          phase: .queued, fraction: 0, title: "T")
        let queuedTile = DownloadTile(tmdbID: 1, title: "T", posterPath: nil, status: queuedStatus)
        let summary = DownloadsSummary(tiles: [queuedTile])
        #expect(summary.leadLine == "T \u{00B7} Starting\u{2026}")
    }

    @Test func helpTextCountsSingularAndPlural() {
        #expect(DownloadsSummary(tiles: [tile("A", fraction: 0.1)]).helpText == "1 downloading to Real\u{2011}Debrid")
        #expect(DownloadsSummary(tiles: [tile("A", fraction: 0.1), tile("B", fraction: 0.2)]).helpText
                == "2 downloading to Real\u{2011}Debrid")
    }
}
