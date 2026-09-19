import Testing
import Foundation
@testable import DebridCore

/// A film used to count as watched at 80% of its runtime, which files a 126-minute feature in the
/// Letterboxd diary twenty-five minutes before it ends. The point to log is when the film is over —
/// when the last line has been spoken and the credits are rolling.
@Suite struct WatchThresholdTests {

    /// Good Will Hunting: 126 minutes.
    private let feature: Double = 126 * 60

    @Test func aFilmWithNoSubtitleIsWatchedNearTheEndRatherThanAtFourFifths() {
        let at = WatchThreshold.finishedAt(duration: feature, lastSubtitleCue: nil)
        #expect(at == 0.92 * feature)
        // ~10 minutes from the end, not the ~25 the old fraction gave.
        #expect(feature - (at ?? 0) < 11 * 60)
    }

    @Test func theEndOfTheDialogueIsWhereAFilmIsWatched() {
        // The last spoken line lands at 1:59:00 of 2:06:00 — the credits from there on.
        let dialogueEnd: Double = 119 * 60
        let at = WatchThreshold.finishedAt(duration: feature, lastSubtitleCue: dialogueEnd)
        #expect(at == dialogueEnd)
    }

    /// Subtitles that caption the credits (or a song over them) would otherwise push the threshold
    /// so close to the final frame that leaving during the credits never logs the film at all.
    @Test func subtitlesRunningToTheLastFrameStillLeaveThirtySeconds() {
        let at = WatchThreshold.finishedAt(duration: feature, lastSubtitleCue: feature - 4)
        #expect(at == feature - 30)
    }

    /// A partial or badly-timed subtitle file is not evidence the film ended there.
    @Test func aSubtitleEndingLongBeforeTheRuntimeIsNotTreatedAsTheCredits() {
        let at = WatchThreshold.finishedAt(duration: feature, lastSubtitleCue: 40 * 60)
        #expect(at == 0.92 * feature)
    }

    @Test func aFileWithNoMeasuredRuntimeHasNoThreshold() {
        #expect(WatchThreshold.finishedAt(duration: 0, lastSubtitleCue: nil) == nil)
        #expect(WatchThreshold.finishedAt(duration: -1, lastSubtitleCue: 100) == nil)
    }

    /// On a short file the thirty-second tail is a bigger slice than the fraction, and subtracting
    /// it would make the threshold EARLIER than the fraction rather than later.
    @Test func theThirtySecondTailNeverPullsAShortFileBelowTheFraction() {
        let short: Double = 60
        let at = WatchThreshold.finishedAt(duration: short, lastSubtitleCue: 59)
        #expect(at == 0.92 * short)
    }

    @Test func aPositionPastTheThresholdCountsAsWatched() {
        let dialogueEnd: Double = 119 * 60
        #expect(WatchThreshold.hasReachedEnd(position: dialogueEnd, duration: feature,
                                             lastSubtitleCue: dialogueEnd))
        #expect(!WatchThreshold.hasReachedEnd(position: dialogueEnd - 1, duration: feature,
                                              lastSubtitleCue: dialogueEnd))
    }

    /// A manual mark records no position and no runtime; dividing there would be a fraction of
    /// nothing, and only real playback can cross the threshold.
    @Test func anUnmeasuredWriteNeverCrossesTheThreshold() {
        #expect(!WatchThreshold.hasReachedEnd(position: 0, duration: 0, lastSubtitleCue: nil))
    }
}
