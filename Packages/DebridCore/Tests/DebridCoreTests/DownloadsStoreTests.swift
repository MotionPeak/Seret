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
                                kind: .movie, title: "T\(torrentID)",
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
            #expect(try await s.find(tmdbID: 99) == nil)
        }
    }
}
