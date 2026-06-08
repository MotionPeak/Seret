import Testing
import Foundation
import SwiftData
@testable import DebridCore

extension SwiftDataSuite {
    @Suite struct MyListStoreTests {
        private func container() throws -> ModelContainer {
            try ModelContainer(for: Profile.self, MyListEntry.self, WatchProgress.self,
                               configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }

        @Test func entryIDIsProfileAndContentKey() {
            #expect(MyListEntry.makeID(profileID: "p1", contentKey: "movie:42") == "p1|movie:42")
        }

        @Test func claimIsIdempotentAndQueryable() async throws {
            let store = MyListStore(modelContainer: try container())
            try await store.claim(profileID: "p1", contentKey: "m", at: Date(timeIntervalSince1970: 1))
            try await store.claim(profileID: "p1", contentKey: "m", at: Date(timeIntervalSince1970: 2))
            #expect(try await store.isClaimed(profileID: "p1", contentKey: "m"))
            #expect(try await store.contentKeys(forProfile: "p1") == ["m"])   // not duplicated
        }

        @Test func unclaimRemovesOnlyThatProfilesEntry() async throws {
            let store = MyListStore(modelContainer: try container())
            try await store.claim(profileID: "p1", contentKey: "m", at: Date(timeIntervalSince1970: 1))
            try await store.claim(profileID: "p2", contentKey: "m", at: Date(timeIntervalSince1970: 1))
            try await store.unclaim(profileID: "p1", contentKey: "m")
            #expect(try await store.isClaimed(profileID: "p1", contentKey: "m") == false)
            #expect(try await store.isClaimed(profileID: "p2", contentKey: "m") == true)
        }

        @Test func contentKeysAreNewestFirstDeduped() async throws {
            let c = try container()
            let store = MyListStore(modelContainer: c)
            // Seed a CloudKit-style duplicate (same id) directly, then a newer distinct claim.
            let ctx = ModelContext(c)
            ctx.insert(MyListEntry(id: "p1|a", profileID: "p1", contentKey: "a",
                                   addedAt: Date(timeIntervalSince1970: 1)))
            ctx.insert(MyListEntry(id: "p1|a", profileID: "p1", contentKey: "a",
                                   addedAt: Date(timeIntervalSince1970: 1)))
            try ctx.save()
            try await store.claim(profileID: "p1", contentKey: "b", at: Date(timeIntervalSince1970: 9))
            #expect(try await store.contentKeys(forProfile: "p1") == ["b", "a"])   // newest first, "a" once
        }
    }
}
