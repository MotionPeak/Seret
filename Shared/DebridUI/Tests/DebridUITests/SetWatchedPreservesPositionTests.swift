import Testing
import Foundation
import DebridCore
@testable import DebridUI

/// Records every `record` call verbatim so a test can see exactly what a manual mark wrote.
private actor MarkSpy: WatchProgressProviding {
    private var rows: [String: [String: WatchState]] = [:]
    private(set) var calls: [(key: String, sourceKey: String, position: Double,
                              duration: Double, finished: Bool)] = []

    init(seed: [String: [String: WatchState]] = [:]) { rows = seed }

    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? {
        rows[profileID]?[key]
    }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws {
        calls.append((contentKey, sourceKey, positionSeconds, durationSeconds, finished))
        rows[profileID, default: [:]][contentKey] = WatchState(
            contentKey: contentKey, sourceKey: sourceKey, positionSeconds: positionSeconds,
            durationSeconds: durationSeconds, finished: finished,
            updatedAt: Date(timeIntervalSince1970: 2))
    }
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
    func deleteProgress(forContentKeys keys: [String]) async throws {}
}

@Suite struct SetWatchedPreservesPositionTests {
    private static let key = "movie:tmdb:7"

    private static func partlyWatched() -> [String: [String: WatchState]] {
        ["p1": [key: WatchState(contentKey: key, sourceKey: "T1#3",
                                positionSeconds: 2400, durationSeconds: 7200,
                                finished: false, updatedAt: Date(timeIntervalSince1970: 1))]]
    }

    /// Marking watched writes `finished`, and used to write position 0 and duration 0 with it.
    /// A long-press on a grid tile is easy to do by accident, and it destroyed the resume point of
    /// whatever it landed on — irrecoverably, since un-marking cannot bring back a position that is
    /// no longer stored. It also zeroed the duration every progress bar for that title divides by.
    @Test func markingWatchedKeepsWhereYouWere() async throws {
        let spy = MarkSpy(seed: Self.partlyWatched())
        await spy.setWatched(true, contentKey: Self.key, sourceKey: "T1#3", profileID: "p1")

        let call = try #require(await spy.calls.first)
        #expect(call.finished == true)
        #expect(call.position == 2400)
        #expect(call.duration == 7200)

        let after = try await spy.progress(forContentKey: Self.key, profileID: "p1")
        #expect(after?.positionSeconds == 2400)
        #expect(after?.durationSeconds == 7200)
        #expect(after?.finished == true)
    }

    /// Marking UNwatched is the one case that should clear the position: "start over" is what it
    /// means. It must also actually stick — carrying a >80% position into the write would let the
    /// finished-fraction rule flip `finished` straight back to true.
    @Test func markingUnwatchedClearsThePositionAndStays() async throws {
        let nearlyDone = ["p1": [Self.key: WatchState(contentKey: Self.key, sourceKey: "T1#3",
                                                      positionSeconds: 6900, durationSeconds: 7200,
                                                      finished: true,
                                                      updatedAt: Date(timeIntervalSince1970: 1))]]
        let spy = MarkSpy(seed: nearlyDone)
        await spy.setWatched(false, contentKey: Self.key, sourceKey: "T1#3", profileID: "p1")

        let call = try #require(await spy.calls.first)
        #expect(call.finished == false)
        #expect(call.position == 0)

        let after = try await spy.progress(forContentKey: Self.key, profileID: "p1")
        #expect(after?.finished == false)
        #expect(after?.positionSeconds == 0)
    }

    /// A title that has never been played has nothing to carry, and must not be blocked by the
    /// extra read.
    @Test func markingAnUnplayedTitleWatchedStillWorks() async throws {
        let spy = MarkSpy()
        await spy.setWatched(true, contentKey: Self.key, sourceKey: "", profileID: "p1")

        let call = try #require(await spy.calls.first)
        #expect(call.finished == true)
        #expect(call.position == 0)
        #expect(call.duration == 0)
    }

    /// The mark must not invent a source key for a title you do not own, but it should carry the
    /// one already recorded rather than blanking it.
    @Test func markingWatchedCarriesTheRecordedSourceWhenNoneIsGiven() async throws {
        let spy = MarkSpy(seed: Self.partlyWatched())
        await spy.setWatched(true, contentKey: Self.key, sourceKey: "", profileID: "p1")

        let call = try #require(await spy.calls.first)
        #expect(call.sourceKey == "T1#3")
    }
}
