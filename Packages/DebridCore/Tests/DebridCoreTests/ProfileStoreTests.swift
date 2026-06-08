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
    }
}
