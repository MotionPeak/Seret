import Testing
import Foundation
@testable import DebridCore

@Suite struct DownloadStatusTests {
    private func info(_ status: String, _ progress: Double) -> TorrentInfo {
        TorrentInfo(id: "T", filename: "f", hash: "h", bytes: 1, progress: progress,
                    status: status, files: [], links: [])
    }

    @Test func downloadedIsReadyAtFull() {
        let s = DownloadStatus(from: info("downloaded", 100), tmdbID: 5)
        #expect(s.phase == .ready)
        #expect(s.fraction == 1.0)
        #expect(s.tmdbID == 5)
    }
    @Test func downloadingCarriesFraction() {
        let s = DownloadStatus(from: info("downloading", 42), tmdbID: 5)
        #expect(s.phase == .downloading)
        #expect(abs(s.fraction - 0.42) < 0.0001)
    }
    @Test func queuedStates() {
        #expect(DownloadStatus(from: info("queued", 0), tmdbID: 1).phase == .queued)
        #expect(DownloadStatus(from: info("magnet_conversion", 0), tmdbID: 1).phase == .queued)
    }
    @Test func terminalIsFailed() {
        for st in ["dead", "virus", "error", "magnet_error"] {
            #expect(DownloadStatus(from: info(st, 0), tmdbID: 1).phase == .failed(st))
        }
    }
}
