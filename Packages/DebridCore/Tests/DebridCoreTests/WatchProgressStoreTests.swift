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
                                   positionSeconds: 42, durationSeconds: 100, finished: false)
            let got = try await store.progress(forContentKey: "movie:tmdb:1")
            #expect(got?.positionSeconds == 42)
            #expect(got?.sourceKey == "T1#0")
            #expect(got?.finished == false)
        }

        @Test func recordUpsertsByContentKey() async throws {
            let store = try store()
            try await store.record(contentKey: "k", sourceKey: "s", positionSeconds: 10,
                                   durationSeconds: 100, finished: false)
            try await store.record(contentKey: "k", sourceKey: "s", positionSeconds: 55,
                                   durationSeconds: 100, finished: true)
            let got = try await store.progress(forContentKey: "k")
            #expect(got?.positionSeconds == 55)   // updated, not duplicated
            #expect(got?.finished == true)
            #expect(try await store.allCount() == 1)   // exactly one row for the key
        }

        @Test func progressIsNilForUnknownKey() async throws {
            #expect(try await store().progress(forContentKey: "nope") == nil)
        }

        @Test func recentlyWatchedIsUnfinishedWithProgressNewestFirst() async throws {
            let store = try store()
            try await store.record(contentKey: "a", sourceKey: "s", positionSeconds: 10,
                                   durationSeconds: 100, finished: false, at: Date(timeIntervalSince1970: 1))
            try await store.record(contentKey: "b", sourceKey: "s", positionSeconds: 20,
                                   durationSeconds: 100, finished: false, at: Date(timeIntervalSince1970: 3))
            try await store.record(contentKey: "c", sourceKey: "s", positionSeconds: 99,
                                   durationSeconds: 100, finished: true,  at: Date(timeIntervalSince1970: 2)) // finished → excluded
            try await store.record(contentKey: "d", sourceKey: "s", positionSeconds: 0,
                                   durationSeconds: 100, finished: false, at: Date(timeIntervalSince1970: 4)) // no progress → excluded
            let recent = try await store.recentlyWatched(limit: 10)
            #expect(recent.map(\.contentKey) == ["b", "a"])   // newest unfinished-with-progress first
        }

        @Test func recentlyWatchedReturnsEmptyForNonPositiveLimit() async throws {
            let store = try store()
            try await store.record(contentKey: "a", sourceKey: "s", positionSeconds: 10,
                                   durationSeconds: 100, finished: false, at: Date(timeIntervalSince1970: 1))
            try await store.record(contentKey: "b", sourceKey: "s", positionSeconds: 20,
                                   durationSeconds: 100, finished: false, at: Date(timeIntervalSince1970: 2))
            #expect(try await store.recentlyWatched(limit: 0) == [])
            #expect(try await store.recentlyWatched(limit: -5) == [])
        }
    }
}
