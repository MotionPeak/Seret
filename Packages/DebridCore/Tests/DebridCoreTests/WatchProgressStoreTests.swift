import Testing
import Foundation
import SwiftData
@testable import DebridCore

// Nested under `SwiftDataSuite` (the serialized parent) — per-suite `.serialized` is NOT enough
// once there are two SwiftData suites; they would run concurrently with each other.
extension SwiftDataSuite {
    @Suite struct WatchProgressStoreTests {
        private func store() throws -> WatchProgressStore {
            let container = try ModelContainer(
                for: WatchProgress.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return WatchProgressStore(modelContainer: container)
        }

        @Test func recordThenReadRoundTrips() async throws {
            let store = try store()
            try await store.record(contentKey: "movie:tmdb:1", sourceKey: "T1#0",
                                   positionSeconds: 42, durationSeconds: 100, finished: false,
                                   profileID: "p1")
            let got = try await store.progress(forContentKey: "movie:tmdb:1", profileID: "p1")
            #expect(got?.positionSeconds == 42)
            #expect(got?.sourceKey == "T1#0")
            #expect(got?.finished == false)
        }

        @Test func recordUpsertsByContentKey() async throws {
            let store = try store()
            try await store.record(contentKey: "k", sourceKey: "s", positionSeconds: 10,
                                   durationSeconds: 100, finished: false, profileID: "p1")
            try await store.record(contentKey: "k", sourceKey: "s", positionSeconds: 55,
                                   durationSeconds: 100, finished: true, profileID: "p1")
            let got = try await store.progress(forContentKey: "k", profileID: "p1")
            #expect(got?.positionSeconds == 55)   // updated, not duplicated
            #expect(got?.finished == true)
            #expect(try await store.allCount() == 1)   // exactly one row for the key
        }

        @Test func progressIsNilForUnknownKey() async throws {
            #expect(try await store().progress(forContentKey: "nope", profileID: "p1") == nil)
        }

        @Test func recentlyWatchedIsUnfinishedWithProgressNewestFirst() async throws {
            let store = try store()
            try await store.record(contentKey: "a", sourceKey: "s", positionSeconds: 10,
                                   durationSeconds: 100, finished: false, profileID: "p1", at: Date(timeIntervalSince1970: 1))
            try await store.record(contentKey: "b", sourceKey: "s", positionSeconds: 20,
                                   durationSeconds: 100, finished: false, profileID: "p1", at: Date(timeIntervalSince1970: 3))
            try await store.record(contentKey: "c", sourceKey: "s", positionSeconds: 99,
                                   durationSeconds: 100, finished: true,  profileID: "p1", at: Date(timeIntervalSince1970: 2)) // finished → excluded
            try await store.record(contentKey: "d", sourceKey: "s", positionSeconds: 0,
                                   durationSeconds: 100, finished: false, profileID: "p1", at: Date(timeIntervalSince1970: 4)) // no progress → excluded
            let recent = try await store.recentlyWatched(limit: 10, profileID: "p1")
            #expect(recent.map(\.contentKey) == ["b", "a"])   // newest unfinished-with-progress first
        }

        @Test func recentlyWatchedReturnsEmptyForNonPositiveLimit() async throws {
            let store = try store()
            try await store.record(contentKey: "a", sourceKey: "s", positionSeconds: 10,
                                   durationSeconds: 100, finished: false, profileID: "p1", at: Date(timeIntervalSince1970: 1))
            try await store.record(contentKey: "b", sourceKey: "s", positionSeconds: 20,
                                   durationSeconds: 100, finished: false, profileID: "p1", at: Date(timeIntervalSince1970: 2))
            #expect(try await store.recentlyWatched(limit: 0, profileID: "p1") == [])
            #expect(try await store.recentlyWatched(limit: -5, profileID: "p1") == [])
        }

        // MARK: - Batched read (one fetch for a whole season's episode keys)

        @Test func batchProgressReturnsStatesForKnownKeysOnly() async throws {
            let store = try store()
            try await store.record(contentKey: "e1", sourceKey: "s", positionSeconds: 10,
                                   durationSeconds: 100, finished: false, profileID: "p1")
            try await store.record(contentKey: "e2", sourceKey: "s", positionSeconds: 90,
                                   durationSeconds: 100, finished: true, profileID: "p1")
            let got = try await store.progress(forContentKeys: ["e1", "e2", "e3"], profileID: "p1")
            #expect(got["e1"]?.positionSeconds == 10)
            #expect(got["e2"]?.finished == true)
            #expect(got["e3"] == nil)                       // never played → absent, not a zero row
            #expect(got.count == 2)
        }

        @Test func batchProgressIsScopedToTheProfile() async throws {
            let store = try store()
            try await store.record(contentKey: "e1", sourceKey: "s", positionSeconds: 10,
                                   durationSeconds: 100, finished: false, profileID: "p1")
            try await store.record(contentKey: "e1", sourceKey: "s", positionSeconds: 77,
                                   durationSeconds: 100, finished: false, profileID: "p2")
            let got = try await store.progress(forContentKeys: ["e1"], profileID: "p2")
            #expect(got["e1"]?.positionSeconds == 77)       // p2's row, not p1's
        }

        @Test func batchProgressPicksTheNewestRowPerKeyWhenCloudKitDuplicated() async throws {
            // CloudKit can sync two rows for the same (key, profile) from different devices —
            // the batch read must converge on the newest, like the single-key read does.
            let container = try ModelContainer(
                for: WatchProgress.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let ctx = ModelContext(container)
            let old = WatchProgress(contentKey: "e1", profileID: "p1")
            old.positionSeconds = 10; old.updatedAt = Date(timeIntervalSince1970: 1)
            let new = WatchProgress(contentKey: "e1", profileID: "p1")
            new.positionSeconds = 55; new.updatedAt = Date(timeIntervalSince1970: 2)
            ctx.insert(old); ctx.insert(new)
            try ctx.save()
            let store = WatchProgressStore(modelContainer: container)
            let got = try await store.progress(forContentKeys: ["e1"], profileID: "p1")
            #expect(got["e1"]?.positionSeconds == 55)       // newest wins
        }

        @Test func batchProgressEmptyKeysReturnsEmpty() async throws {
            #expect(try await store().progress(forContentKeys: [], profileID: "p1").isEmpty)
        }
    }
}
