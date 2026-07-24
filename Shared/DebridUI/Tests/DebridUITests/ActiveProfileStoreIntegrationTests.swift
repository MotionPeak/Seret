import Testing
import Foundation
import SwiftData
@testable import DebridUI
import DebridCore

/// Drives ActiveProfileStore through the REAL ProfileStore (in-memory SwiftData, no CloudKit) to
/// isolate whether an empty roster / no-op create is a logic bug or a CloudKit/environment bug.
@MainActor
@Suite struct ActiveProfileStoreIntegrationTests {
    @Test func loadAndCreatePopulateRosterWithRealStore() async throws {
        let container = try ModelContainer(
            for: Profile.self, MyListEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = ProfileStore(modelContainer: container)
        let aps = ActiveProfileStore(provider: store)

        await aps.loadAndResolve()
        #expect(aps.roster.count == 1)                       // owner auto-created
        #expect(aps.roster.first?.avatar == "🍿")

        await aps.create(name: "Kid", colorTag: "blue", avatar: "🦊")
        #expect(aps.roster.count == 2)                       // new profile persisted + reloaded
        #expect(aps.roster.contains { $0.name == "Kid" && $0.avatar == "🦊" })
    }
}
