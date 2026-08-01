import Testing
import Foundation
import SwiftData
@testable import DebridCore

extension SwiftDataSuite {
    /// ETA behaviour through the monitor. The estimator itself is covered by `ETAEstimatorTests`;
    /// this checks the monitor threads it per-torrent and across polls.
    @Suite struct DownloadMonitorTests {
        private final class FakeLister: DownloadListing, @unchecked Sendable {
            var torrentsToReturn: [Torrent]
            init(_ t: [Torrent]) { torrentsToReturn = t }
            func torrents(page: Int, limit: Int) async throws -> [Torrent] { torrentsToReturn }
        }

        private struct NoResolver: DownloadIdentityResolving {
            func identity(filename: String, infoHash: String) async -> DownloadIdentity? { nil }
        }

        private final class Clock: @unchecked Sendable {
            var value = Date(timeIntervalSince1970: 0)
        }

        private func torrent(_ id: String, _ status: String, _ progress: Double,
                             bytes: Int = 1000, speed: Int? = nil) -> Torrent {
            Torrent(id: id, filename: "f.mkv", hash: "h\(id)", bytes: bytes,
                    host: "real-debrid.com", progress: progress, status: status,
                    added: "2026-08-01T10:00:00.000Z", links: [], speed: speed)
        }

        private func emptyStore() throws -> DownloadsStore {
            let c = try ModelContainer(for: DownloadRequest.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return DownloadsStore(modelContainer: c)
        }

        /// 3000 bytes remaining at RD's reported 100 B/s = 30s, before any rate is observed.
        @Test func firstPollEstimatesFromReportedSpeed() async throws {
            let m = DownloadMonitor(lister: FakeLister([torrent("A", "downloading", 25,
                                                                bytes: 4000, speed: 100)]),
                                    store: try emptyStore(), resolver: NoResolver())
            #expect(try await m.poll()[0].secondsRemaining == 30.0)
        }

        /// Across two polls 10s apart the monitor observes 1000 bytes of real progress
        /// (100 B/s) and uses that instead of the deliberately absurd reported figure.
        @Test func secondPollEstimatesFromObservedThroughput() async throws {
            let lister = FakeLister([torrent("A", "downloading", 25, bytes: 4000, speed: 999_999)])
            let clock = Clock()
            let m = DownloadMonitor(lister: lister, store: try emptyStore(),
                                    resolver: NoResolver(), now: { clock.value })
            _ = try await m.poll()
            lister.torrentsToReturn = [torrent("A", "downloading", 50, bytes: 4000, speed: 999_999)]
            clock.value = Date(timeIntervalSince1970: 10)
            #expect(try await m.poll()[0].secondsRemaining == 20.0)
        }

        @Test func aQueuedDownloadHasNoEstimate() async throws {
            let m = DownloadMonitor(lister: FakeLister([torrent("A", "queued", 0)]),
                                    store: try emptyStore(), resolver: NoResolver())
            let status = try await m.poll()[0]
            #expect(status.phase == .queued)
            #expect(status.secondsRemaining == nil)
        }

        /// Two concurrent downloads must not share an estimator.
        @Test func estimatorsArePerTorrent() async throws {
            let lister = FakeLister([torrent("A", "downloading", 25, bytes: 4000, speed: 100),
                                     torrent("B", "downloading", 50, bytes: 8000, speed: 200)])
            let m = DownloadMonitor(lister: lister, store: try emptyStore(), resolver: NoResolver())
            let statuses = try await m.poll().sorted { $0.torrentID < $1.torrentID }
            #expect(statuses[0].secondsRemaining == 30.0)    // 3000 / 100
            #expect(statuses[1].secondsRemaining == 20.0)    // 4000 / 200
        }

        @Test func statusCarriesSizeSpeedAndSeeders() async throws {
            let t = Torrent(id: "A", filename: "f.mkv", hash: "h", bytes: 4096,
                            host: "real-debrid.com", progress: 25, status: "downloading",
                            added: "2026-08-01T10:00:00.000Z", links: [], speed: 512, seeders: 9)
            let m = DownloadMonitor(lister: FakeLister([t]), store: try emptyStore(),
                                    resolver: NoResolver())
            let status = try await m.poll()[0]
            #expect(status.bytesTotal == 4096)
            #expect(status.speedBytesPerSecond == 512)
            #expect(status.seeders == 9)
        }
    }
}
