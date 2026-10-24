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

        /// A torrent that was downloading and is now `downloaded` must be announced once, so the
        /// library refreshes and the "ready" notification fires.
        @Test func aFinishedTorrentIsReportedReadyOnce() async throws {
            let s = try await store(seed: [record("A", "movie:tmdb:7")])
            let lister = FakeLister([torrent("A", "downloading", 90)])
            let m = monitor(lister, s)
            _ = try await m.poll()

            lister.torrentsToReturn = [torrent("A", "downloaded", 100)]
            let second = try await m.poll()
            #expect(second.count == 1)
            #expect(second[0].phase == .ready)
            #expect(second[0].contentKey == "movie:tmdb:7")

            // Announced once only — a third poll must not repeat it.
            #expect(try await m.poll().isEmpty)
        }

        @Test func aFinishedTorrentDropsItsRecord() async throws {
            let s = try await store(seed: [record("A", "movie:tmdb:7")])
            let lister = FakeLister([torrent("A", "downloading", 90)])
            let m = monitor(lister, s)
            _ = try await m.poll()
            lister.torrentsToReturn = [torrent("A", "downloaded", 100)]
            _ = try await m.poll()
            #expect(try await s.all().isEmpty)
        }

        @Test func aFailedTorrentIsReportedFailed() async throws {
            let s = try await store(seed: [record("A", "movie:tmdb:7")])
            let lister = FakeLister([torrent("A", "downloading", 10)])
            let m = monitor(lister, s)
            _ = try await m.poll()
            lister.torrentsToReturn = [torrent("A", "dead", 10)]
            let second = try await m.poll()
            #expect(second[0].phase == .failed("dead"))
        }

        /// Deleted from RD elsewhere. Previously this leaked the record forever, because the old
        /// monitor skipped a torrent whose info fetch failed.
        @Test func aVanishedTorrentIsReportedFailedAndDropsItsRecord() async throws {
            let s = try await store(seed: [record("A", "movie:tmdb:7")])
            let lister = FakeLister([torrent("A", "downloading", 10)])
            let m = monitor(lister, s)
            _ = try await m.poll()

            lister.torrentsToReturn = []
            let second = try await m.poll()
            #expect(second.count == 1)
            #expect(second[0].phase == .failed("removed"))
            #expect(second[0].contentKey == "movie:tmdb:7")
            #expect(try await s.all().isEmpty)
        }

        /// A record whose torrent was never seen active (app restarted mid-download, then the
        /// torrent finished while we were away) must still be reconciled away.
        @Test func aRecordForATorrentRDNoLongerListsIsCleanedUp() async throws {
            let s = try await store(seed: [record("GONE", "movie:tmdb:7")])
            let m = monitor(FakeLister([]), s)
            let statuses = try await m.poll()
            #expect(statuses.count == 1)
            #expect(statuses[0].phase == .failed("removed"))
            #expect(try await s.all().isEmpty)
        }

        /// A download started elsewhere has no record, so only the previously-active bookkeeping
        /// can notice it finished. Without that announcement the library never refreshes and the
        /// finished title never appears.
        @Test func aFinishedForeignTorrentIsAnnouncedAndReleasesItsEstimator() async throws {
            let s = try await store(seed: [])
            let found = DownloadIdentity(contentKey: "movie:tmdb:42", tmdbID: 42,
                                         kind: .movie, title: "Foreign")
            let lister = FakeLister([torrent("A", "downloading", 50, bytes: 1000, speed: 100)])
            let m = monitor(lister, s, resolver: FixedResolver(identity: found))
            _ = try await m.poll()

            lister.torrentsToReturn = [torrent("A", "downloaded", 100)]
            let second = try await m.poll()
            #expect(second.count == 1)
            #expect(second[0].phase == .ready)
            #expect(second[0].contentKey == "movie:tmdb:42")
            #expect(await m.trackedEstimatorCount == 0)

            #expect(try await m.poll().isEmpty)   // announced once only
        }


        // MARK: - Two accounts: one answering, one not

        /// A lister that reports which accounts could not answer, as the composite does.
        private final class FakeListing: DownloadListing, @unchecked Sendable {
            var page: TorrentListing
            init(_ page: TorrentListing) { self.page = page }
            func torrents(page: Int, limit: Int) async throws -> [Torrent] { self.page.torrents }
            func listing(page: Int, limit: Int) async throws -> TorrentListing { self.page }
        }

        /// An RD blip must not read as every RD download having been deleted: no `.failed("removed")`
        /// and the record — the only place the exact title lives — survives. When RD answers again
        /// the download carries on as active.
        @Test func monitorKeepsUnavailableProvidersDownloads() async throws {
            let s = try await store(seed: [record("A", "movie:tmdb:7")])
            let lister = FakeListing(TorrentListing(torrents: [torrent("A", "downloading", 30)]))
            let m = DownloadMonitor(lister: lister, store: s, resolver: NoResolver())
            #expect(try await m.poll().map(\.phase) == [.downloading])

            lister.page = TorrentListing(torrents: [], unavailable: [.realDebrid])
            let duringOutage = try await m.poll()
            #expect(duringOutage.isEmpty)
            #expect(try await s.all().map(\.torrentID) == ["A"])

            lister.page = TorrentListing(torrents: [torrent("A", "downloading", 60)])
            let recovered = try await m.poll()
            #expect(recovered.map(\.torrentID) == ["A"])
            #expect(recovered.first?.phase == .downloading)
            #expect(recovered.first?.contentKey == "movie:tmdb:7")
        }

        /// Kept as previously active through the outage, so a download that finished meanwhile is
        /// still announced ready — the library refresh hangs off that announcement. A download
        /// started elsewhere has no record to fall back on, so only that bookkeeping notices.
        @Test func aDownloadThatFinishedDuringAnOutageIsStillAnnouncedReady() async throws {
            let s = try await store(seed: [])
            let lister = FakeListing(TorrentListing(torrents: [torrent("A", "downloading", 30)]))
            let m = DownloadMonitor(lister: lister, store: s, resolver: NoResolver())
            _ = try await m.poll()

            lister.page = TorrentListing(torrents: [], unavailable: [.realDebrid])
            _ = try await m.poll()

            lister.page = TorrentListing(torrents: [torrent("A", "downloaded", 100)])
            let after = try await m.poll()
            #expect(after.map(\.torrentID) == ["A"])
            #expect(after.map(\.phase) == [.ready])
        }

        /// Only the account that failed is held back: the other's vanished download is still
        /// reported removed, and its record swept.
        @Test func onlyTheUnavailableAccountsDownloadsAreHeldBack() async throws {
            let s = try await store(seed: [record("A", "movie:tmdb:7"), record("tb:5", "movie:tmdb:8")])
            let lister = FakeListing(TorrentListing(torrents: [torrent("A", "downloading", 30),
                                                               torrent("tb:5", "downloading", 30)]))
            let m = DownloadMonitor(lister: lister, store: s, resolver: NoResolver())
            _ = try await m.poll()

            lister.page = TorrentListing(torrents: [], unavailable: [.realDebrid])
            let statuses = try await m.poll()
            #expect(statuses.map(\.torrentID) == ["tb:5"])
            #expect(statuses.first?.phase == .failed("removed"))
            #expect(try await s.all().map(\.torrentID) == ["A"])
        }

        /// A record of an account that is simply not signed in is not held back: signing out is
        /// not an outage.
        @Test func aSignedOutAccountsRecordIsStillSwept() async throws {
            let s = try await store(seed: [record("A", "movie:tmdb:7")])
            let m = DownloadMonitor(lister: FakeListing(TorrentListing(torrents: [])), store: s,
                                    resolver: NoResolver())
            #expect(try await m.poll().map(\.phase) == [.failed("removed")])
            #expect(try await s.all().isEmpty)
        }
    }
}
