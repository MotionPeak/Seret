import Testing
import Foundation
@testable import DebridCore

@Suite struct WatchlistStoreTests {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wl-\(UUID().uuidString).json")
    }

    func entry(_ slug: String, position: Int, tmdbID: Int? = nil) -> WatchlistEntry {
        WatchlistEntry(slug: slug, name: "\(slug) (1994)", year: 1994,
                       position: position, tmdbID: tmdbID,
                       resolvedAt: tmdbID == nil ? nil : Date(timeIntervalSince1970: 1))
    }

    @Test func savesAndLoadsEntries() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WatchlistStore(fileURL: url)
        store.save([entry("speed", position: 0, tmdbID: 1637), entry("heat", position: 1)])

        let loaded = store.load()
        #expect(loaded.count == 2)
        #expect(loaded[0].slug == "speed")
        #expect(loaded[0].tmdbID == 1637)
        #expect(loaded[1].tmdbID == nil)
    }

    @Test func loadsInPositionOrderWhateverOrderItWasSavedIn() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WatchlistStore(fileURL: url)
        store.save([entry("c", position: 2), entry("a", position: 0), entry("b", position: 1)])
        #expect(store.load().map(\.slug) == ["a", "b", "c"])
    }

    @Test func aMissingFileLoadsEmptyRatherThanThrowing() {
        #expect(WatchlistStore(fileURL: tempURL()).load().isEmpty)
    }

    @Test func aNilLocationDegradesToEmptyAndSavingIsHarmless() {
        let store = WatchlistStore(fileURL: nil)
        store.save([entry("speed", position: 0)])      // must not crash
        #expect(store.load().isEmpty)
    }

    @Test func corruptContentLoadsEmpty() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        #expect(WatchlistStore(fileURL: url).load().isEmpty)
    }

    @Test func anUnmatchedEntryIsDistinguishableFromAnUntriedOne() {
        let untried = WatchlistEntry(slug: "a", name: "A (1994)", year: 1994, position: 0)
        let tried = WatchlistEntry(slug: "b", name: "B (1994)", year: 1994, position: 1,
                                   tmdbID: nil, resolvedAt: Date())
        #expect(untried.isResolved == false)
        #expect(tried.isResolved == true)
        #expect(tried.tmdbID == nil)
    }
}
