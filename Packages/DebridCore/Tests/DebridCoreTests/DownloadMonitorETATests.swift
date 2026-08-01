import Testing
import Foundation
import SwiftData
@testable import DebridCore

extension SwiftDataSuite {
    @Suite struct DownloadMonitorETATests {
        /// A fake whose answers can change between polls, so a rate can be observed.
        private final class StepInfo: DownloadInfoProviding, @unchecked Sendable {
            var infos: [String: TorrentInfo]
            init(_ infos: [String: TorrentInfo]) { self.infos = infos }
            func info(id: String) async throws -> TorrentInfo {
                guard let i = infos[id] else { throw CancellationError() }
                return i
            }
        }

        /// A settable clock. A plain `var` captured by the `@Sendable` closure `DownloadMonitor`
        /// takes would not compile under Swift 6 strict concurrency, so the mutation lives behind
        /// a reference type.
        private final class Clock: @unchecked Sendable {
            var value = Date(timeIntervalSince1970: 0)
        }

        private func store(seed: [DownloadRequestData]) async throws -> DownloadsStore {
            let c = try ModelContainer(for: DownloadRequest.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let s = DownloadsStore(modelContainer: c)
            for r in seed { try await s.upsert(r) }
            return s
        }

        private func info(_ id: String, _ status: String, _ progress: Double,
                          bytes: Int = 1000, speed: Int? = nil) -> TorrentInfo {
            TorrentInfo(id: id, filename: "f", hash: "h", bytes: bytes, progress: progress,
                        status: status, files: [], links: [], speed: speed)
        }

        private func request(_ tid: String, _ key: String) -> DownloadRequestData {
            DownloadRequestData(torrentID: tid, contentKey: key, tmdbID: 7, infoHash: "h",
                                kind: .movie, title: "t", requestedAt: Date(timeIntervalSince1970: 0))
        }

        @Test func statusCarriesTheRequestsContentKey() async throws {
            let s = try await store(seed: [request("A", "movie:tmdb:7")])
            let m = DownloadMonitor(info: StepInfo(["A": info("A", "downloading", 30)]), store: s)
            let statuses = try await m.poll()
            #expect(statuses.count == 1)
            #expect(statuses[0].contentKey == "movie:tmdb:7")
        }

        @Test func statusCarriesSizeSpeedAndSeeders() async throws {
            let s = try await store(seed: [request("A", "movie:tmdb:7")])
            let i = TorrentInfo(id: "A", filename: "f", hash: "h", bytes: 4096, progress: 25,
                                status: "downloading", files: [], links: [], speed: 512, seeders: 9)
            let m = DownloadMonitor(info: StepInfo(["A": i]), store: s)
            let status = try await m.poll()[0]
            #expect(status.bytesTotal == 4096)
            #expect(status.speedBytesPerSecond == 512)
            #expect(status.seeders == 9)
        }

        /// First poll has no observed rate, so it falls back to RD's reported speed:
        /// 3000 bytes remaining at 100 B/s = 30s.
        @Test func firstPollEstimatesFromReportedSpeed() async throws {
            let s = try await store(seed: [request("A", "movie:tmdb:7")])
            let i = info("A", "downloading", 25, bytes: 4000, speed: 100)
            let m = DownloadMonitor(info: StepInfo(["A": i]), store: s)
            let status = try await m.poll()[0]
            #expect(status.secondsRemaining == 30.0)
        }

        /// Across two polls 10s apart the monitor observes 1000 bytes of real progress
        /// (100 B/s) and uses that instead of the reported figure. 2000 remain -> 20s.
        @Test func secondPollEstimatesFromObservedThroughput() async throws {
            let s = try await store(seed: [request("A", "movie:tmdb:7")])
            let fake = StepInfo(["A": info("A", "downloading", 25, bytes: 4000, speed: 999_999)])
            let clock = Clock()
            let m = DownloadMonitor(info: fake, store: s, now: { clock.value })
            _ = try await m.poll()
            fake.infos["A"] = info("A", "downloading", 50, bytes: 4000, speed: 999_999)
            clock.value = Date(timeIntervalSince1970: 10)
            let status = try await m.poll()[0]
            #expect(status.secondsRemaining == 20.0)
        }

        @Test func aQueuedDownloadHasNoEstimate() async throws {
            let s = try await store(seed: [request("A", "movie:tmdb:7")])
            let m = DownloadMonitor(info: StepInfo(["A": info("A", "queued", 0)]), store: s)
            let status = try await m.poll()[0]
            #expect(status.phase == .queued)
            #expect(status.secondsRemaining == nil)
        }
    }
}
