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

    private func listItem(_ status: String, _ progress: Double,
                          bytes: Int = 1000, speed: Int? = nil) -> Torrent {
        Torrent(id: "T", filename: "f.mkv", hash: "h", bytes: bytes, host: "real-debrid.com",
                progress: progress, status: status, added: "2026-08-01T10:00:00.000Z",
                links: [], speed: speed)
    }

    @Test func buildsFromAListItem() {
        let s = DownloadStatus(from: listItem("downloading", 40, bytes: 2048, speed: 256),
                               contentKey: "movie:tmdb:7", tmdbID: 7, title: "Dune",
                               posterPath: "/d.jpg", secondsRemaining: 5)
        #expect(s.phase == .downloading)
        #expect(abs(s.fraction - 0.4) < 0.0001)
        #expect(s.bytesTotal == 2048)
        #expect(s.speedBytesPerSecond == 256)
        #expect(s.title == "Dune")
        #expect(s.posterPath == "/d.jpg")
        #expect(s.secondsRemaining == 5)
    }

    /// Both inits must classify identically — they are the same RD vocabulary.
    @Test func listItemAndInfoAgreeOnPhase() {
        for status in ["downloaded", "downloading", "queued", "dead", "compressing"] {
            let fromInfo = DownloadStatus(from: info(status, 0), tmdbID: 1).phase
            let fromList = DownloadStatus(from: listItem(status, 0), tmdbID: 1).phase
            #expect(fromInfo == fromList, "phase mismatch for \(status)")
        }
    }

    @Test func titleDefaultsToEmpty() {
        #expect(DownloadStatus(from: info("downloading", 10), tmdbID: 1).title == "")
    }

    @Test func storeKeyIsTheContentKeyWhenIdentified() {
        let s = DownloadStatus(from: info("downloading", 10), contentKey: "movie:tmdb:7", tmdbID: 7)
        #expect(s.storeKey == "movie:tmdb:7")
    }

    /// Two unidentifiable foreign downloads must not collide on an empty key.
    @Test func storeKeyFallsBackToTheTorrentIDWhenUnidentified() {
        let a = DownloadStatus(torrentID: "A", tmdbID: 0, phase: .downloading, fraction: 0)
        let b = DownloadStatus(torrentID: "B", tmdbID: 0, phase: .downloading, fraction: 0)
        #expect(a.storeKey == "torrent:A")
        #expect(a.storeKey != b.storeKey)
    }
}
