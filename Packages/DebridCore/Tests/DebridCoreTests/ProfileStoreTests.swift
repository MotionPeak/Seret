import Testing
import Foundation
import SwiftData
@testable import DebridCore

extension SwiftDataSuite {
    @Suite struct ProfileStoreTests {
        private func container() throws -> ModelContainer {
            try ModelContainer(for: Profile.self, MyListEntry.self, WatchProgress.self,
                               configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }

        @Test func profileDTOMirrorsModel() throws {
            let m = Profile(id: "p1", name: "Shahar", colorTag: "gold",
                            createdAt: Date(timeIntervalSince1970: 10))
            let dto = ProfileDTO(m)
            #expect(dto.id == "p1")
            #expect(dto.name == "Shahar")
            #expect(dto.colorTag == "gold")
            #expect(dto.createdAt == Date(timeIntervalSince1970: 10))
        }

        @Test func createThenAllReturnsByCreatedAtAscending() async throws {
            let store = ProfileStore(modelContainer: try container())
            _ = try await store.create(name: "B", colorTag: "blue", id: "b",
                                       at: Date(timeIntervalSince1970: 20))
            _ = try await store.create(name: "A", colorTag: "gold", id: "a",
                                       at: Date(timeIntervalSince1970: 10))
            let all = try await store.all()
            #expect(all.map(\.id) == ["a", "b"])   // oldest first
            #expect(all.first?.name == "A")
        }

        @Test func renameChangesName() async throws {
            let store = ProfileStore(modelContainer: try container())
            _ = try await store.create(name: "Old", colorTag: "gold", id: "p1",
                                       at: Date(timeIntervalSince1970: 1))
            try await store.rename(id: "p1", to: "New")
            #expect(try await store.all().first?.name == "New")
        }

        @Test func deleteCascadesMyListAndProgress() async throws {
            let c = try container()
            let store = ProfileStore(modelContainer: c)
            _ = try await store.create(name: "P1", colorTag: "gold", id: "p1",
                                       at: Date(timeIntervalSince1970: 1))
            _ = try await store.create(name: "P2", colorTag: "blue", id: "p2",
                                       at: Date(timeIntervalSince1970: 2))
            // Seed p1-owned My List + progress, and one p2 row that must survive.
            let ctx = ModelContext(c)
            ctx.insert(MyListEntry(id: "p1|m", profileID: "p1", contentKey: "m"))
            ctx.insert(WatchProgress(contentKey: "m", profileID: "p1"))
            ctx.insert(WatchProgress(contentKey: "n", profileID: "p2"))
            try ctx.save()

            try await store.delete(id: "p1")

            #expect(try await store.all().map(\.id) == ["p2"])
            let ctx2 = ModelContext(c)
            #expect(try ctx2.fetch(FetchDescriptor<MyListEntry>()).isEmpty)
            let progress = try ctx2.fetch(FetchDescriptor<WatchProgress>())
            #expect(progress.map(\.profileID) == ["p2"])   // p1's progress gone, p2's kept
        }

        @Test func ensureOwnerCreatesProfileAndMigratesNilProgress() async throws {
            let c = try container()
            let store = ProfileStore(modelContainer: c)
            let ctx = ModelContext(c)
            ctx.insert(WatchProgress(contentKey: "old", positionSeconds: 5))   // profileID nil
            try ctx.save()

            let owner = try await store.ensureOwnerProfileAndMigrate(
                ownerName: "Me", colorTag: "gold", id: "owner", at: Date(timeIntervalSince1970: 1))

            #expect(owner.id == "owner")
            #expect(try await store.all().map(\.id) == ["owner"])
            let migrated = try ModelContext(c).fetch(FetchDescriptor<WatchProgress>())
            #expect(migrated.first?.profileID == "owner")   // nil row re-keyed to owner
        }

        @Test func ensureOwnerIsIdempotentWhenProfilesExist() async throws {
            let store = ProfileStore(modelContainer: try container())
            _ = try await store.create(name: "Existing", colorTag: "blue", id: "p1",
                                       at: Date(timeIntervalSince1970: 1))
            let owner = try await store.ensureOwnerProfileAndMigrate(
                ownerName: "Me", colorTag: "gold", id: "owner", at: Date(timeIntervalSince1970: 2))
            #expect(owner.id == "p1")                       // returns the existing earliest profile
            #expect(try await store.all().map(\.id) == ["p1"])   // no second profile created
        }
    }
}
