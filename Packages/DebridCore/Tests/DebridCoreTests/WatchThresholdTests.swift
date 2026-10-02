import Testing
import Foundation
@testable import DebridCore

/// A film used to count as watched at 80% of its runtime, which files a 126-minute feature in the
/// Letterboxd diary twenty-five minutes before it ends. The point to log is when the film is over —
/// when the last line has been spoken and the credits are rolling.
@Suite struct WatchThresholdTests {

    /// Good Will Hunting: 126 minutes.
    private let feature: Double = 126 * 60

    /// 92% of a two-hour feature is ten minutes from its end — the rating prompt then asked about
    /// a film that was still playing. With nothing to say where the film ends, five minutes out is
    /// inside the credits of nearly any feature, and late is the side to err on.
    @Test func aFilmWithNoSubtitleIsWatchedFiveMinutesFromTheEnd() {
        let at = WatchThreshold.finishedAt(duration: feature, lastSubtitleCue: nil)
        #expect(at == feature - 5 * 60)
    }

    /// Five minutes is most of a short film; the fraction keeps the fallback near the end there.
    @Test func aShortFileWithNoSubtitleStillUsesTheFraction() {
        let short: Double = 20 * 60
        #expect(WatchThreshold.finishedAt(duration: short, lastSubtitleCue: nil) == 0.92 * short)
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
        #expect(at == feature - 5 * 60)
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

    // MARK: - Where the credits start (TheIntroDB)

    @Test func whereTheCreditsStartIsWhereAFilmIsWatched() {
        let credits: Double = 120 * 60
        let at = WatchThreshold.finishedAt(duration: feature, lastSubtitleCue: nil,
                                           creditsStart: credits)
        #expect(at == credits)
    }

    /// A final scene with no dialogue: the last line is spoken, the film carries on. The later of
    /// the two is the one that is past the film.
    @Test func withBothTheLaterOfTheLastLineAndTheCreditsWins() {
        let lastLine: Double = 116 * 60, credits: Double = 120 * 60
        #expect(WatchThreshold.finishedAt(duration: feature, lastSubtitleCue: lastLine,
                                          creditsStart: credits) == credits)
        #expect(WatchThreshold.finishedAt(duration: feature, lastSubtitleCue: credits,
                                          creditsStart: lastLine) == credits)
    }

    /// Crowdsourced timestamps can belong to a different cut of the film.
    @Test func creditsStartingImplausiblyEarlyAreIgnored() {
        let at = WatchThreshold.finishedAt(duration: feature, lastSubtitleCue: nil,
                                           creditsStart: 30 * 60)
        #expect(at == feature - 5 * 60)
    }

    @Test func creditsPastTheEndOfThisFileStillLeaveThirtySeconds() {
        let at = WatchThreshold.finishedAt(duration: feature, lastSubtitleCue: nil,
                                           creditsStart: feature + 600)
        #expect(at == feature - 30)
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
