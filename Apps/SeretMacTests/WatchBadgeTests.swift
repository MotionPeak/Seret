import DebridCore
import Foundation
import Testing
@testable import Seret

@Suite struct WatchBadgeTests {
    private func state(position: Double, duration: Double, finished: Bool) -> WatchState {
        WatchState(contentKey: "k", sourceKey: "s", positionSeconds: position, durationSeconds: duration,
                  finished: finished, updatedAt: .now)
    }

    @Test func noStateIsNoBadge() {
        #expect(WatchBadge(nil) == .none)
    }

    @Test func finishedIsWatchedEvenWithAPosition() {
        #expect(WatchBadge(state(position: 4000, duration: 8000, finished: true)) == .watched)
    }

    @Test func halfwayIsHalfProgress() {
        #expect(WatchBadge(state(position: 4000, duration: 8000, finished: false)) == .progress(0.5))
    }

    @Test func aSliverStillShows() {
        #expect(WatchBadge(state(position: 1, duration: 8000, finished: false)) == .progress(0.02))
    }

    @Test func unknownLengthIsNoBadge() {
        #expect(WatchBadge(state(position: 400, duration: 0, finished: false)) == .none)
    }

    @Test func pastTheEndClampsToFull() {
        #expect(WatchBadge(state(position: 9000, duration: 8000, finished: false)) == .progress(1))
    }
}
