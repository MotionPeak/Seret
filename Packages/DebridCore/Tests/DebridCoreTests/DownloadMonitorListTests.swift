import Testing
import Foundation
import SwiftData
@testable import DebridCore

extension SwiftDataSuite {
    @Suite struct DownloadMonitorListTests {
        private final class FakeLister: DownloadListing, @unchecked Sendable {
            var torrentsToReturn: [Torrent]
            var calls = 0
            init(_ t: [Torrent]) { torrentsToReturn = t }
            func torrents(page: Int, limit: Int) async throws -> [Torrent] {
                calls += 1
                return torrentsToReturn
            }
        }

        private struct FixedResolver: DownloadIdentityResolving {
            let identity: DownloadIdentity?
            func identity(filename: String, infoHash: String) async -> DownloadIdentity? {
                identity
            }
        }

        private struct NoResolver: DownloadIdentityResolving {
            func identity(filename: String, infoHash: String) async -> DownloadIdentity? { nil }
        }

        private func torrent(_ id: String, _ status: String, _ progress: Double,
                             hash: String = "h", bytes: Int = 1000,
                             speed: Int? = nil, filename: String = "f.mkv") -> Torrent {
            Torrent(id: id, filename: filename, hash: hash, bytes: bytes,
                    host: "real-debrid.com", progress: progress, status: status,
                    added: "2026-08-01T10:00:00.000Z", links: [], speed: speed)
        }

        private func store(seed: [DownloadRequestData]) async throws -> DownloadsStore {
            let c = try ModelContainer(for: DownloadRequest.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let s = DownloadsStore(modelContainer: c)
            for r in seed { try await s.upsert(r) }
            return s
        }

        private func record(_ tid: String, _ key: String, tmdb: Int = 7,
                            title: String = "Recorded") -> DownloadRequestData {
            DownloadRequestData(torrentID: tid, contentKey: key, tmdbID: tmdb, infoHash: "h",
                                kind: .movie, title: title, posterPath: "/rec.jpg",
                                requestedAt: Date(timeIntervalSince1970: 0))
        }

        private func monitor(_ lister: FakeLister, _ s: DownloadsStore,
                             resolver: any DownloadIdentityResolving = NoResolver()) -> DownloadMonitor {
            DownloadMonitor(lister: lister, store: s, resolver: resolver)
        }

        @Test func reportsAnActiveTorrentFromTheList() async throws {
            let s = try await store(seed: [record("A", "movie:tmdb:7")])
            let m = monitor(FakeLister([torrent("A", "downloading", 30)]), s)
            let statuses = try await m.poll()
            #expect(statuses.count == 1)
            #expect(statuses[0].phase == .downloading)
            #expect(statuses[0].contentKey == "movie:tmdb:7")
        }

        /// A local record wins over the resolver: it has the exact tmdbID and episode key we
        /// recorded when starting the download, where the resolver only guesses from a filename.
        @Test func aLocalRecordSuppliesIdentityWithoutTheResolver() async throws {
            let s = try await store(seed: [record("A", "show:tmdb:1399:s1e2", tmdb: 1399,
                                                  title: "Recorded Title")])
            let wrong = DownloadIdentity(contentKey: "movie:tmdb:999", tmdbID: 999,
                                         kind: .movie, title: "Wrong")
            let m = monitor(FakeLister([torrent("A", "downloading", 10)]), s,
                            resolver: FixedResolver(identity: wrong))
            let status = try await m.poll()[0]
            #expect(status.contentKey == "show:tmdb:1399:s1e2")
            #expect(status.tmdbID == 1399)
            #expect(status.title == "Recorded Title")
            #expect(status.posterPath == "/rec.jpg")
        }

        /// The whole point of the slice: a download started elsewhere still shows up.
        @Test func aForeignTorrentIsResolvedAndReported() async throws {
            let s = try await store(seed: [])
            let found = DownloadIdentity(contentKey: "movie:tmdb:42", tmdbID: 42,
                                         kind: .movie, title: "Foreign", posterPath: "/f.jpg")
            let m = monitor(FakeLister([torrent("Z", "downloading", 55, filename: "Foreign.2024.mkv")]),
                            s, resolver: FixedResolver(identity: found))
            let statuses = try await m.poll()
            #expect(statuses.count == 1)
            #expect(statuses[0].contentKey == "movie:tmdb:42")
            #expect(statuses[0].title == "Foreign")
        }

        /// An unidentifiable foreign torrent still deserves a progress row, just an unnamed one.
        @Test func anUnresolvableForeignTorrentIsStillReported() async throws {
            let s = try await store(seed: [])
            let m = monitor(FakeLister([torrent("Z", "downloading", 55)]), s)
            let statuses = try await m.poll()
            #expect(statuses.count == 1)
            #expect(statuses[0].contentKey == "")
            #expect(statuses[0].tmdbID == 0)
        }

        /// Finished and idle torrents are the overwhelming majority of an RD account.
        @Test func completedAndIdleTorrentsAreNotReportedAsDownloads() async throws {
            let s = try await store(seed: [])
            let m = monitor(FakeLister([torrent("A", "downloaded", 100),
                                        torrent("B", "downloading", 20)]), s)
            let statuses = try await m.poll()
            #expect(statuses.map(\.torrentID) == ["B"])
        }

        @Test func allActiveRDStatusesCount() async throws {
            let s = try await store(seed: [])
            let active = ["queued", "magnet_conversion", "waiting_files_selection",
                          "downloading", "compressing", "uploading"]
            let m = monitor(FakeLister(active.enumerated().map { torrent("T\($0.offset)", $0.element, 0) }), s)
            #expect(try await m.poll().count == active.count)
        }

        /// A row written before `contentKey` existed carries an empty key. It must fall through to
        /// the resolver rather than being treated as authoritative identity.
        @Test func aRecordWithNoContentKeyFallsThroughToTheResolver() async throws {
            let s = try await store(seed: [record("A", "")])
            let found = DownloadIdentity(contentKey: "movie:tmdb:42", tmdbID: 42,
                                         kind: .movie, title: "Resolved")
            let m = monitor(FakeLister([torrent("A", "downloading", 10)]), s,
                            resolver: FixedResolver(identity: found))
            let status = try await m.poll()[0]
            #expect(status.contentKey == "movie:tmdb:42")
            #expect(status.title == "Resolved")
        }

        @Test func oneListCallPerPoll() async throws {
            let s = try await store(seed: [])
            let lister = FakeLister([torrent("A", "downloading", 10), torrent("B", "downloading", 20)])
            let m = monitor(lister, s)
            _ = try await m.poll()
            #expect(lister.calls == 1)
        }
    }
}
