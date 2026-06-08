import Testing
import Foundation
import SwiftData
@testable import DebridCore

// Nested under the serialized SwiftDataSuite parent (repo convention — multiple SwiftData
// suites must not run concurrently; two in-memory ModelContainers can SIGSEGV the runner).
extension SwiftDataSuite {
    @Suite struct WatchProgressReconcileTests {
        private func container() throws -> ModelContainer {
            try ModelContainer(for: WatchProgress.self,
                               configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }

        @Test func profileIDDefaultsToNil() throws {
            let row = WatchProgress(contentKey: "k")
            #expect(row.profileID == nil)
        }

        @Test func profileIDPersistsRoundTrip() throws {
            let c = try container()
            let ctx = ModelContext(c)
            let row = WatchProgress(contentKey: "k")
            row.profileID = "alice"
            ctx.insert(row)
            try ctx.save()
            let fetched = try ctx.fetch(FetchDescriptor<WatchProgress>()).first
            #expect(fetched?.profileID == "alice")
        }

        /// Insert duplicate rows for one key straight into the store, as CloudKit would after a
        /// two-device merge.
        private func seedDuplicates(_ c: ModelContainer) throws {
            let ctx = ModelContext(c)
            ctx.insert(WatchProgress(contentKey: "dupe", sourceKey: "old", positionSeconds: 10,
                                     durationSeconds: 100, finished: false,
                                     updatedAt: Date(timeIntervalSince1970: 1)))
            ctx.insert(WatchProgress(contentKey: "dupe", sourceKey: "new", positionSeconds: 80,
                                     durationSeconds: 100, finished: false,
                                     updatedAt: Date(timeIntervalSince1970: 5)))
            try ctx.save()
        }

        @Test func progressReturnsNewestAndPrunesDuplicates() async throws {
            let c = try container()
            try seedDuplicates(c)
            let store = WatchProgressStore(modelContainer: c)
            let got = try await store.progress(forContentKey: "dupe")
            #expect(got?.positionSeconds == 80)        // the newest row wins
            #expect(got?.sourceKey == "new")
            #expect(try await store.allCount() == 1)   // the stale duplicate is gone
        }

        @Test func recentlyWatchedDedupesByContentKey() async throws {
            let c = try container()
            try seedDuplicates(c)
            let store = WatchProgressStore(modelContainer: c)
            let feed = try await store.recentlyWatched(limit: 20)
            #expect(feed.count == 1)                   // one entry per key, not two
            #expect(feed.first?.positionSeconds == 80)
        }
    }
}
