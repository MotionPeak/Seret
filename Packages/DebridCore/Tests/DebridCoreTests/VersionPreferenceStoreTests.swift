import Testing
import Foundation
import SwiftData
@testable import DebridCore

extension SwiftDataSuite {
    @Suite struct VersionPreferenceStoreTests {
        private func store() throws -> VersionPreferenceStore {
            let c = try ModelContainer(for: VersionPreference.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return VersionPreferenceStore(modelContainer: c)
        }

        @Test func choosingThenReadingRoundTrips() async throws {
            let s = try store()
            try await s.setChoice(contentKey: "movie:tmdb:7", sourceKey: "T1#3",
                                  at: Date(timeIntervalSince1970: 10))
            #expect(try await s.preferredSourceKey(forContentKey: "movie:tmdb:7") == "T1#3")
        }

        @Test func noPreferenceReadsAsNil() async throws {
            #expect(try await store().preferredSourceKey(forContentKey: "movie:tmdb:7") == nil)
        }

        /// One row per title — choosing again replaces rather than accumulating.
        @Test func choosingAgainReplaces() async throws {
            let s = try store()
            try await s.setChoice(contentKey: "movie:tmdb:7", sourceKey: "T1#3",
                                  at: Date(timeIntervalSince1970: 10))
            try await s.setChoice(contentKey: "movie:tmdb:7", sourceKey: "T2#1",
                                  at: Date(timeIntervalSince1970: 20))
            #expect(try await s.preferredSourceKey(forContentKey: "movie:tmdb:7") == "T2#1")
            #expect(try await s.count() == 1)
        }

        @Test func clearingRemovesThePreference() async throws {
            let s = try store()
            try await s.setChoice(contentKey: "movie:tmdb:7", sourceKey: "T1#3",
                                  at: Date(timeIntervalSince1970: 10))
            try await s.clearChoice(contentKey: "movie:tmdb:7")
            #expect(try await s.preferredSourceKey(forContentKey: "movie:tmdb:7") == nil)
        }

        @Test func titlesAreIndependent() async throws {
            let s = try store()
            try await s.setChoice(contentKey: "movie:tmdb:1", sourceKey: "A#-",
                                  at: Date(timeIntervalSince1970: 10))
            try await s.setChoice(contentKey: "movie:tmdb:2", sourceKey: "B#-",
                                  at: Date(timeIntervalSince1970: 10))
            #expect(try await s.preferredSourceKey(forContentKey: "movie:tmdb:1") == "A#-")
            #expect(try await s.preferredSourceKey(forContentKey: "movie:tmdb:2") == "B#-")
        }

        /// CloudKit cannot enforce uniqueness, so two devices can both write a row for one title.
        /// The newest wins, exactly as WatchProgressStore reconciles duplicates.
        @Test func cloudKitDuplicatesReconcileToTheNewest() async throws {
            let s = try store()
            try await s.insertRawForTest(contentKey: "movie:tmdb:7", sourceKey: "OLD#1",
                                         at: Date(timeIntervalSince1970: 10))
            try await s.insertRawForTest(contentKey: "movie:tmdb:7", sourceKey: "NEW#1",
                                         at: Date(timeIntervalSince1970: 99))
            #expect(try await s.preferredSourceKey(forContentKey: "movie:tmdb:7") == "NEW#1")
        }
    }
}
