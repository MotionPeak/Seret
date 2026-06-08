import Testing
import Foundation
import SwiftData
@testable import DebridCore

// Nested under the serialized SwiftDataSuite parent (repo convention — multiple SwiftData
// suites must not run concurrently; two in-memory ModelContainers can SIGSEGV the runner).
extension SwiftDataSuite {
    @Suite struct WatchProgressReconcileTests {
        private func container() throws -> ModelContainer {
            try ModelContainer(for: WatchProgress.self,
                               configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }

        @Test func profileIDDefaultsToNil() throws {
            let row = WatchProgress(contentKey: "k")
            #expect(row.profileID == nil)
        }

        @Test func profileIDPersistsRoundTrip() throws {
            let c = try container()
            let ctx = ModelContext(c)
            let row = WatchProgress(contentKey: "k")
            row.profileID = "alice"
            ctx.insert(row)
            try ctx.save()
            let fetched = try ctx.fetch(FetchDescriptor<WatchProgress>()).first
            #expect(fetched?.profileID == "alice")
        }
    }
}
