import Testing
import Foundation
@testable import DebridCore

/// `finished` answers "does this count as watched" — it flips at 80% so a title stops cluttering
/// Continue Watching once you have effectively seen it. Seven separate call sites also used it to
/// answer a DIFFERENT question, "is there a point to resume from", and the two are not the same:
/// the last 20% of a feature is twenty-odd minutes of film. Crossing 80% silently threw the
/// position away, so leaving at 1:45 of a 2:10 film and coming back offered "Play", from zero.
@Suite struct WatchStateResumeTests {

    private func state(position: Double, duration: Double, finished: Bool) -> WatchState {
        WatchState(contentKey: "movie:tmdb:1", sourceKey: "t#-", positionSeconds: position,
                   durationSeconds: duration, finished: finished, updatedAt: Date())
    }

    @Test func aTitlePastTheWatchedThresholdStillResumesWhereItWasLeft() {
        // 1:45 into a 2:10 film: finished (81%), but 25 minutes are still unwatched.
        let s = state(position: 6300, duration: 7800, finished: true)
        #expect(s.resumePosition == 6300)
    }

    @Test func aTitleWatchedToTheEndHasNothingLeftToResumeInto() {
        let s = state(position: 7790, duration: 7800, finished: true)
        #expect(s.resumePosition == nil)
    }

    @Test func aTitleNeverStartedHasNoResumePoint() {
        #expect(state(position: 0, duration: 7800, finished: false).resumePosition == nil)
    }

    @Test func aTitleMarkedWatchedByHandHasNoResumePoint() {
        // `setWatched` records the flag alone — no position, no length.
        #expect(state(position: 0, duration: 0, finished: true).resumePosition == nil)
    }

    /// A length of 0 means nobody measured it (a hand-marked row), so the flag is all there is.
    @Test func withoutAKnownLengthTheFinishedFlagStillDecides() {
        #expect(state(position: 120, duration: 0, finished: false).resumePosition == 120)
        #expect(state(position: 120, duration: 0, finished: true).resumePosition == nil)
    }

    @Test func partwayThroughAnUnfinishedTitleResumesAsBefore() {
        #expect(state(position: 1800, duration: 7800, finished: false).resumePosition == 1800)
    }
}
