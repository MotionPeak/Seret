import Testing
import Foundation
import SwiftData
@testable import DebridCore

extension SwiftDataSuite {
    @Suite struct ProfileStoreTests {
        private func container() throws -> ModelContainer {
            try ModelContainer(for: Profile.self, MyListEntry.self,
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

        @Test func createCarriesAvatar() async throws {
            let store = ProfileStore(modelContainer: try container())
            let p = try await store.create(name: "Kid", colorTag: "blue", avatar: "🦊",
                                           id: "k", at: Date(timeIntervalSince1970: 1))
            #expect(p.avatar == "🦊")
            #expect(try await store.all().first?.avatar == "🦊")
        }

        @Test func renameChangesName() async throws {
            let store = ProfileStore(modelContainer: try container())
            _ = try await store.create(name: "Old", colorTag: "gold", id: "p1",
                                       at: Date(timeIntervalSince1970: 1))
            try await store.rename(id: "p1", to: "New")
            #expect(try await store.all().first?.name == "New")
        }

        @Test func updateChangesNameColorAndAvatar() async throws {
            let store = ProfileStore(modelContainer: try container())
            _ = try await store.create(name: "Old", colorTag: "gold", avatar: "bottts:A", id: "p1",
                                       at: Date(timeIntervalSince1970: 1))
            try await store.update(id: "p1", name: "New", colorTag: "blue", avatar: "pixel-art:Z")
            let p = try await store.all().first
            #expect(p?.name == "New")
            #expect(p?.colorTag == "blue")
            #expect(p?.avatar == "pixel-art:Z")
        }

        @Test func updateUnknownIdIsANoOp() async throws {
            let store = ProfileStore(modelContainer: try container())
            try await store.update(id: "ghost", name: "x", colorTag: "red", avatar: "y")
            #expect(try await store.all().isEmpty)
        }

        @Test func deleteCascadesMyList() async throws {
            let c = try container()
            let store = ProfileStore(modelContainer: c)
            _ = try await store.create(name: "P1", colorTag: "gold", id: "p1",
                                       at: Date(timeIntervalSince1970: 1))
            _ = try await store.create(name: "P2", colorTag: "blue", id: "p2",
                                       at: Date(timeIntervalSince1970: 2))
            let ctx = ModelContext(c)
            ctx.insert(MyListEntry(id: "p1|m", profileID: "p1", contentKey: "m"))
            try ctx.save()

            try await store.delete(id: "p1")

            #expect(try await store.all().map(\.id) == ["p2"])
            // Watch progress is Trakt's now (one account app-wide), so there is nothing
            // per-profile left to cascade to — only My List.
            #expect(try ModelContext(c).fetch(FetchDescriptor<MyListEntry>()).isEmpty)
        }

        @Test func ensureOwnerCreatesProfile() async throws {
            let c = try container()
            let store = ProfileStore(modelContainer: c)

            let owner = try await store.ensureOwnerProfileAndMigrate(
                ownerName: "Me", colorTag: "gold", id: "owner", at: Date(timeIntervalSince1970: 1))

            #expect(owner.id == "owner")
            #expect(try await store.all().map(\.id) == ["owner"])
        }

        @Test func allDedupesByIdKeepingEarliest() async throws {
            let c = try container()
            // Two devices each created the default owner before CloudKit synced → same id, two rows.
            let ctx = ModelContext(c)
            ctx.insert(Profile(id: Profile.defaultOwnerID, name: "Me", colorTag: "gold",
                               createdAt: Date(timeIntervalSince1970: 5)))
            ctx.insert(Profile(id: Profile.defaultOwnerID, name: "Me", colorTag: "gold",
                               createdAt: Date(timeIntervalSince1970: 2)))
            try ctx.save()
            let all = try await ProfileStore(modelContainer: c).all()
            #expect(all.map(\.id) == [Profile.defaultOwnerID])   // one entry, not two
            #expect(all.first?.createdAt == Date(timeIntervalSince1970: 2))   // earliest kept
        }

        @Test func ensureOwnerUsesDefaultIdWhenNotSpecified() async throws {
            // The seam path (no explicit id) must use the stable shared id so devices converge.
            let store = ProfileStore(modelContainer: try container())
            let owner = try await store.ensureOwnerProfileAndMigrate(
                ownerName: "Me", colorTag: "gold", id: Profile.defaultOwnerID,
                at: Date(timeIntervalSince1970: 1))
            #expect(owner.id == Profile.defaultOwnerID)
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

        /// The cascade was written when history lived on Trakt, as one account for the whole app.
        /// Trakt is gone and watch state is per-profile and local, so every deleted profile left
        /// its rows behind for good -- invisible, unreachable, and syncing to every device forever.
        /// The confirmation dialog told the viewer that progress would be removed.
        @Test func deletingAProfileTakesItsWatchProgressWithIt() async throws {
            let container = try ModelContainer(
                for: Profile.self, MyListEntry.self, VersionPreference.self, WatchProgress.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let profiles = ProfileStore(modelContainer: container)
            let watch = LocalWatchStore(modelContainer: container)

            let mine = try await profiles.create(name: "Me", colorTag: "gold", avatar: "a",
                                                 id: "p1", at: Date(timeIntervalSince1970: 1))
            _ = try await profiles.create(name: "You", colorTag: "blue", avatar: "b",
                                          id: "p2", at: Date(timeIntervalSince1970: 2))
            try await watch.write(contentKey: "movie:tmdb:7", sourceKey: "T1#1",
                                  positionSeconds: 100, durationSeconds: 6000, finished: false,
                                  profileID: "p1", at: Date(timeIntervalSince1970: 10))
            try await watch.write(contentKey: "movie:tmdb:8", sourceKey: "T2#1",
                                  positionSeconds: 200, durationSeconds: 6000, finished: false,
                                  profileID: "p2", at: Date(timeIntervalSince1970: 11))

            try await profiles.delete(id: mine.id)

            #expect(try await watch.state(forContentKey: "movie:tmdb:7", profileID: "p1") == nil)
            // …and the OTHER profile's history is untouched.
            #expect(try await watch.state(forContentKey: "movie:tmdb:8", profileID: "p2") != nil)
            #expect(try await watch.count() == 1)
        }
    }
}
