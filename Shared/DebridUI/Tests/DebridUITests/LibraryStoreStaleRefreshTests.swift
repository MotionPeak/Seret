import Testing
import Foundation
import DebridCore
@testable import DebridUI

/// tvOS keeps a suspended app alive for days and the shell loaded the library exactly once, at
/// mount — so a title added from DMM, the phone or the Real-Debrid site never appeared until the
/// app was killed. `refreshIfStale` is what a foregrounded app or a re-selected page calls.
@MainActor
@Suite struct LibraryStoreStaleRefreshTests {
    private actor RefreshCounter {
        private(set) var value = 0
        func bump() { value += 1 }
    }

    private struct CountingLibrary: LibraryProviding {
        let counter: RefreshCounter
        func loadCached() -> [MediaItem]? { nil }
        func refresh() async throws -> [MediaItem] {
            await counter.bump()
            return [MediaItem(id: "1", kind: .movie, title: "One", year: 2024, sources: [], seasons: [])]
        }
        func remove(_ item: MediaItem) async throws {}
        func removeVersion(_ item: MediaItem, source: MediaSource) async throws {}
    }

    private final class Clock { var now = Date(timeIntervalSince1970: 1_000_000) }

    @Test func reloadsOnlyOnceTheLibraryHasGoneStale() async {
        let counter = RefreshCounter()
        let clock = Clock()
        let store = LibraryStore(library: CountingLibrary(counter: counter), now: { clock.now })
        await store.load()
        #expect(await counter.value == 1)

        clock.now += 60
        #expect(store.refreshIfStale(maxAge: 120) == false)    // fresh: nothing to do
        clock.now += 61
        #expect(store.refreshIfStale(maxAge: 120) == true)     // 121s old: refresh

        for _ in 0..<2_000 where await counter.value < 2 { await Task.yield() }
        #expect(await counter.value == 2)
    }

    @Test func aStoreThatNeverLoadedIsStale() async {
        let counter = RefreshCounter()
        let store = LibraryStore(library: CountingLibrary(counter: counter), now: { Date() })
        #expect(store.refreshIfStale(maxAge: 120) == true)
        for _ in 0..<2_000 where await counter.value < 1 { await Task.yield() }
        #expect(await counter.value == 1)
    }
}
