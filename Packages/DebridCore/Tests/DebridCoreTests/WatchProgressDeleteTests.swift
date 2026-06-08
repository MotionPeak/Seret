import Testing
import Foundation
import SwiftData
@testable import DebridCore

// Nested under `SwiftDataSuite` (the serialized parent) — per-suite `.serialized` is NOT enough
// once there are multiple SwiftData suites; they would run concurrently with each other.
extension SwiftDataSuite {
    @Suite struct WatchProgressDeleteTests {
        private func store() throws -> WatchProgressStore {
            let container = try ModelContainer(
                for: WatchProgress.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return WatchProgressStore(modelContainer: container)
        }

        @Test func deletesOnlyTheGivenKeys() async throws {
            let s = try store()
            try await s.record(contentKey: "movie:a", sourceKey: "t#-", positionSeconds: 10,
                               durationSeconds: 100, finished: false, profileID: "p1")
            try await s.record(contentKey: "show:x:s1e1", sourceKey: "t#-", positionSeconds: 5,
                               durationSeconds: 100, finished: false, profileID: "p1")
            try await s.record(contentKey: "movie:keep", sourceKey: "t#-", positionSeconds: 7,
                               durationSeconds: 100, finished: false, profileID: "p1")

            try await s.deleteProgress(forContentKeys: ["movie:a", "show:x:s1e1"])

            #expect(try await s.progress(forContentKey: "movie:a", profileID: "p1") == nil)
            #expect(try await s.progress(forContentKey: "show:x:s1e1", profileID: "p1") == nil)
            #expect(try await s.progress(forContentKey: "movie:keep", profileID: "p1") != nil)
        }

        @Test func emptyKeysIsANoOp() async throws {
            let s = try store()
            try await s.record(contentKey: "movie:a", sourceKey: "t#-", positionSeconds: 10,
                               durationSeconds: 100, finished: false, profileID: "p1")
            try await s.deleteProgress(forContentKeys: [])
            #expect(try await s.progress(forContentKey: "movie:a", profileID: "p1") != nil)
        }
    }
}
