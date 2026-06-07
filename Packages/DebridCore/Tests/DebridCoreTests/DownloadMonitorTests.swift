import Testing
import Foundation
import SwiftData
@testable import DebridCore

extension SwiftDataSuite {
    @Suite struct DownloadMonitorTests {
        private func store(seed: [DownloadRequestData]) async throws -> DownloadsStore {
            let c = try ModelContainer(for: DownloadRequest.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let s = DownloadsStore(modelContainer: c)
            for r in seed { try await s.upsert(r) }
            return s
        }
        private func data(_ tid: String, _ tmdb: Int) -> DownloadRequestData {
            DownloadRequestData(torrentID: tid, tmdbID: tmdb, infoHash: "h", kind: .movie,
                                title: "t", requestedAt: Date(timeIntervalSince1970: 0))
        }
        private func info(_ id: String, _ status: String, _ progress: Double) -> TorrentInfo {
            TorrentInfo(id: id, filename: "f", hash: "h", bytes: 1, progress: progress,
                        status: status, files: [], links: [])
        }

        @Test func reportsProgressAndKeepsDownloadingRecord() async throws {
            let s = try await store(seed: [data("A", 1)])
            let infos = FakeInfo(["A": info("A", "downloading", 30)])
            let monitor = DownloadMonitor(info: infos, store: s)
            let statuses = try await monitor.poll()
            #expect(statuses.count == 1)
            #expect(statuses[0].phase == .downloading)
            #expect(abs(statuses[0].fraction - 0.30) < 0.0001)
            #expect(try await s.all().count == 1)   // still tracked
        }

        @Test func clearsReadyAndFailedRecords() async throws {
            let s = try await store(seed: [data("A", 1), data("B", 2)])
            let infos = FakeInfo(["A": info("A", "downloaded", 100), "B": info("B", "dead", 0)])
            let monitor = DownloadMonitor(info: infos, store: s)
            let statuses = try await monitor.poll()
            let phases = statuses.map(\.phase)
            #expect(phases.contains(.ready))
            #expect(phases.contains(.failed("dead")))
            #expect(try await s.all().isEmpty)       // both terminal records cleared
        }

        @Test func skipsRequestWhoseInfoFails() async throws {
            let s = try await store(seed: [data("A", 1)])
            let infos = FakeInfo([:])   // no entry → info throws
            let monitor = DownloadMonitor(info: infos, store: s)
            let statuses = try await monitor.poll()
            #expect(statuses.isEmpty)
            #expect(try await s.all().count == 1)    // kept for next pass
        }
    }
}

private struct FakeInfo: DownloadInfoProviding {
    let map: [String: TorrentInfo]
    init(_ map: [String: TorrentInfo]) { self.map = map }
    func info(id: String) async throws -> TorrentInfo {
        guard let i = map[id] else { throw FakeInfoError.missing }
        return i
    }
}
private enum FakeInfoError: Error { case missing }
