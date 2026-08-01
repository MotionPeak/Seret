import Testing
import Foundation
import SwiftData
@testable import DebridCore

extension SwiftDataSuite {
    @Suite struct DownloadsStoreTests {
        private func store() throws -> DownloadsStore {
            let c = try ModelContainer(for: DownloadRequest.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return DownloadsStore(modelContainer: c)
        }
        private func req(_ torrentID: String, tmdb: Int) -> DownloadRequestData {
            DownloadRequestData(torrentID: torrentID, tmdbID: tmdb, infoHash: "h\(torrentID)",
                                kind: .movie, title: "T\(torrentID)", posterPath: "/p\(torrentID).jpg",
                                requestedAt: Date(timeIntervalSince1970: 0))
        }

        @Test func upsertAllAndDelete() async throws {
            let s = try store()
            try await s.upsert(req("A", tmdb: 1))
            try await s.upsert(req("B", tmdb: 2))
            #expect(try await s.all().count == 2)
            try await s.delete(torrentID: "A")
            let rest = try await s.all()
            #expect(rest.map(\.torrentID) == ["B"])
        }

        @Test func upsertReplacesSameTorrent() async throws {
            let s = try store()
            try await s.upsert(req("A", tmdb: 1))
            try await s.upsert(req("A", tmdb: 1))   // same torrentID
            #expect(try await s.all().count == 1)   // deduped, not duplicated
        }

        @Test func findByTMDB() async throws {
            let s = try store()
            try await s.upsert(req("A", tmdb: 7))
            #expect(try await s.find(tmdbID: 7)?.torrentID == "A")
            #expect(try await s.find(tmdbID: 7)?.posterPath == "/pA.jpg")   // poster survives persistence
            #expect(try await s.find(tmdbID: 99) == nil)
        }

        @Test func contentKeyRoundTripsThroughTheStore() async throws {
            let s = try store()
            try await s.upsert(DownloadRequestData(
                torrentID: "T1", contentKey: "show:tmdb:1399:s1e2", tmdbID: 1399,
                infoHash: "h", kind: .show, title: "Winter Is Coming",
                requestedAt: Date(timeIntervalSince1970: 10)))
            let all = try await s.all()
            #expect(all.count == 1)
            #expect(all[0].contentKey == "show:tmdb:1399:s1e2")
        }

        /// Two episodes of one show are two separate rows — they share a tmdbID and must not
        /// overwrite each other.
        @Test func twoEpisodesOfOneShowCoexist() async throws {
            let s = try store()
            try await s.upsert(DownloadRequestData(
                torrentID: "T1", contentKey: "show:tmdb:1399:s1e1", tmdbID: 1399,
                infoHash: "h1", kind: .show, title: "S1E1",
                requestedAt: Date(timeIntervalSince1970: 10)))
            try await s.upsert(DownloadRequestData(
                torrentID: "T2", contentKey: "show:tmdb:1399:s1e2", tmdbID: 1399,
                infoHash: "h2", kind: .show, title: "S1E2",
                requestedAt: Date(timeIntervalSince1970: 20)))
            let keys = Set(try await s.all().map(\.contentKey))
            #expect(keys == ["show:tmdb:1399:s1e1", "show:tmdb:1399:s1e2"])
        }

        /// An older row written before this field existed decodes with an empty key, not a crash.
        @Test func contentKeyDefaultsToEmpty() async throws {
            let s = try store()
            try await s.upsert(DownloadRequestData(
                torrentID: "T9", tmdbID: 5, infoHash: "h", kind: .movie, title: "t",
                requestedAt: Date(timeIntervalSince1970: 0)))
            #expect(try await s.all()[0].contentKey == "")
        }
    }
}
