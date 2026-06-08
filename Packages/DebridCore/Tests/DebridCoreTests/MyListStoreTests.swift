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
    }
}
