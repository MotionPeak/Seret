import Testing
import Foundation
@testable import DebridCore

/// What "resume" means for a title the viewer has finished.
struct ResumePositionTests {
    private func state(position: Double, duration: Double, finished: Bool) -> WatchState {
        WatchState(contentKey: "k", sourceKey: "s", positionSeconds: position,
                   durationSeconds: duration, finished: finished,
                   updatedAt: Date(timeIntervalSince1970: 1))
    }

    /// A manual mark carries the position forward so un-marking restores your place — but that
    /// position can be anywhere, and offering it as a resume point made "mark watched" quietly
    /// mean "resume from the middle".
    @Test func aTitleMarkedWatchedPartWayThroughOffersNoResume() {
        #expect(state(position: 2400, duration: 7200, finished: true).resumePosition == nil)
    }

    /// …but a title finished by actually watching to the tail still resumes there. Crossing the
    /// 80% mark sets `finished`, and being able to pick up the last stretch is the point.
    @Test func aTitleFinishedNearTheEndStillResumesThere() {
        #expect(state(position: 6300, duration: 7200, finished: true).resumePosition == 6300)
    }

    /// An unfinished title resumes wherever it is.
    @Test func anUnfinishedTitleResumesWhereItWas() {
        #expect(state(position: 2400, duration: 7200, finished: false).resumePosition == 2400)
    }

    /// Right at the end there is nothing left to resume.
    @Test func aPositionInTheFinalMomentsOffersNoResume() {
        #expect(state(position: 7195, duration: 7200, finished: true).resumePosition == nil)
        #expect(state(position: 7195, duration: 7200, finished: false).resumePosition == nil)
    }

    @Test func aTitleNeverStartedOffersNoResume() {
        #expect(state(position: 0, duration: 7200, finished: false).resumePosition == nil)
    }
}
