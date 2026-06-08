import Testing
import Foundation
import SwiftData
@testable import DebridCore

extension SwiftDataSuite {
    @Suite struct ProfileStoreTests {
        private func container() throws -> ModelContainer {
            try ModelContainer(for: Profile.self, WatchProgress.self,
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
    }
}
