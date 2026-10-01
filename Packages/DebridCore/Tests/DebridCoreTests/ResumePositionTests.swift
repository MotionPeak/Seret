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

    /// `finished` now flips where the dialogue ends (the last subtitle cue, or 92% of the runtime),
    /// so what is left of a finished film is its credits. Stopping four minutes into an eight-minute
    /// roll offered "Resume 2:02:00" — and Play dropped the viewer into the credits.
    @Test func aFinishedFilmDoesNotResumeIntoItsCredits() {
        #expect(state(position: 7320, duration: 7800, finished: true).resumePosition == nil)
        #expect(state(position: 1250, duration: 1320, finished: true).resumePosition == nil)  // an episode
    }

    /// A short file's last 8% is under the fixed 90 seconds: an 11-minute cartoon stopped at 9:50
    /// stayed on Continue Watching (not finished) while Play started it from 0:00.
    @Test func aShortFileStoppedBeforeItsFinishLineStillResumes() {
        #expect(state(position: 590, duration: 660, finished: false).resumePosition == 590)
    }
}
