import Testing
import Foundation
import DebridCore
@testable import DebridUI

/// Mark Watched carries the position forward precisely so it can be undone. Un-marking used to
/// write 0 regardless, so an accidental long-press destroyed the resume point anyway — one step
/// later, on the very press meant to undo it.
@Suite struct MarkWatchedRoundTripTests {
    /// Stores exactly what it is told, like `LocalWatchStore` below its fallback threshold.
    private actor Store: WatchProgressProviding {
        private var rows: [String: WatchState]
        init(_ rows: [String: WatchState] = [:]) { self.rows = rows }
        func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { rows[key] }
        func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                    durationSeconds: Double, finished: Bool, profileID: String) async throws {
            rows[contentKey] = WatchState(contentKey: contentKey, sourceKey: sourceKey,
                                          positionSeconds: positionSeconds,
                                          durationSeconds: durationSeconds, finished: finished,
                                          updatedAt: Date())
        }
        func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
        func deleteProgress(forContentKeys keys: [String]) async throws {}
        func row(_ key: String) -> WatchState? { rows[key] }
    }

    private func state(_ position: Double, of duration: Double, finished: Bool) -> WatchState {
        WatchState(contentKey: "m", sourceKey: "s", positionSeconds: position,
                   durationSeconds: duration, finished: finished, updatedAt: Date())
    }

    @Test func undoingAnAccidentalMarkGivesThePlaceBack() async {
        let store = Store(["m": state(3600, of: 7200, finished: false)])
        await store.setWatched(true, contentKey: "m", sourceKey: "s", profileID: "p")
        #expect(await store.row("m")?.finished == true)
        #expect(await store.row("m")?.resumePosition == nil)     // marked: the page offers Play
        await store.setWatched(false, contentKey: "m", sourceKey: "s", profileID: "p")
        #expect(await store.row("m")?.finished == false)
        #expect(await store.row("m")?.resumePosition == 3600)    // undone: Resume 1:00:00 again
    }

    /// Watched to its end, un-marking means watching it again — from the start.
    @Test func unmarkingATitleWatchedToItsEndStartsOver() async {
        let store = Store(["m": state(6840, of: 7200, finished: true)])
        await store.setWatched(false, contentKey: "m", sourceKey: "s", profileID: "p")
        #expect(await store.row("m")?.positionSeconds == 0)
        #expect(await store.row("m")?.durationSeconds == 7200)    // still told apart from a rating row
    }

    /// Continue Watching's "Mark Unwatched" on a card you only started is how you clear it: that
    /// one still throws the place away.
    @Test func clearingAStartedTitleStillThrowsThePlaceAway() async {
        let store = Store(["m": state(600, of: 7200, finished: false)])
        await store.setWatched(false, contentKey: "m", sourceKey: "s", profileID: "p")
        #expect(await store.row("m")?.positionSeconds == 0)
    }
}
