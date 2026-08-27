import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// The hand-dialled subtitle offset — the last resort when a subtitle does not match the file.
///
/// It exists because `SubtitleRetimer` cannot help with a MUXED track: an external file can be
/// rescaled before it is attached, but a track inside the container cannot be rewritten. It also
/// covers the case the automatic path cannot see, where OpenSubtitles declares no rate or declares
/// the wrong one.
@MainActor
@Suite struct PlayerSubtitleDelayTests {

    private func model(engine: FakeVideoPlayerEngine = FakeVideoPlayerEngine()) -> PlayerModel {
        PlayerModel(request: Fixture.request(sources: [Fixture.movieSource()]), engine: engine,
                    unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _ in }, subtitles: FakeSubtitleProvider())
    }

    @Test func nudgingAccumulatesAndReachesTheEngine() {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine: engine)

        m.adjustSubtitleDelay(by: 0.5)
        m.adjustSubtitleDelay(by: 0.5)
        m.adjustSubtitleDelay(by: -0.25)

        #expect(m.subtitleDelay == 0.75)
        #expect(engine.subtitleDelays == [0.5, 1.0, 0.75])
    }

    @Test func resetReturnsToTheFilesOwnTiming() {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine: engine)
        m.adjustSubtitleDelay(by: 2)

        m.resetSubtitleDelay()

        #expect(m.subtitleDelay == 0)
        #expect(engine.subtitleDelays.last == 0)
    }

    @Test func theOffsetIsClampedToSomethingSane() {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine: engine)

        m.adjustSubtitleDelay(by: 10_000)
        #expect(m.subtitleDelay == PlayerModel.maxSubtitleDelay)

        m.adjustSubtitleDelay(by: -100_000)
        #expect(m.subtitleDelay == -PlayerModel.maxSubtitleDelay)
    }

    @Test func aNonZeroOffsetIsReassertedWhenTracksChange() {
        // Attaching a slave or switching track can land the engine on a fresh subtitle output that
        // knows nothing of what was dialled in — the same hazard the volume boost is re-asserted for.
        let engine = FakeVideoPlayerEngine()
        let m = model(engine: engine)
        m.adjustSubtitleDelay(by: 1.5)
        let before = engine.subtitleDelays.count

        m.refreshTracks()

        #expect(engine.subtitleDelays.count == before + 1)
        #expect(engine.subtitleDelays.last == 1.5)
    }

    // MARK: - Drift correction (the muxed-track case)

    /// Drive the model to a known playback position.
    private func atPosition(_ seconds: Double, engine: FakeVideoPlayerEngine) async -> PlayerModel {
        let m = model(engine: engine)
        m.start()
        engine.emit(.time(PlaybackTime(position: seconds, duration: 5400)))
        await m.waitForIdleForTesting()
        return m
    }

    @Test func driftCorrectionGrowsWithPositionAtTheRateOfTheError() async {
        // A muxed track cannot be rewritten, so the ONLY answer is an offset recomputed as the
        // drift grows. 25fps cues on a 23.976 file run 4.096% early: an hour in that is 2m27s.
        let engine = FakeVideoPlayerEngine()
        engine.videoFPS = 23.976
        let m = await atPosition(3600, engine: engine)

        m.setSubtitleSourceFPS(25)

        #expect(abs(m.subtitleDriftDelay - 147.46) < 0.5)
        #expect(abs((engine.subtitleDelays.last ?? 0) - 147.46) < 0.5)
    }

    @Test func theCorrectionIsRecomputedOnEveryTick() async {
        let engine = FakeVideoPlayerEngine()
        engine.videoFPS = 23.976
        let m = await atPosition(600, engine: engine)
        m.setSubtitleSourceFPS(25)
        let atTenMinutes = engine.subtitleDelays.last ?? 0

        engine.emit(.time(PlaybackTime(position: 2400, duration: 5400)))
        await m.waitForIdleForTesting()

        // Left un-recomputed the offset would still be the ten-minute one and the drift would
        // simply resume from there — the whole point is that it tracks position.
        let atForty = try! #require(engine.subtitleDelays.last)
        #expect(atForty > atTenMinutes * 3)
        #expect(abs(atTenMinutes - 24.58) < 0.5)
        #expect(abs(atForty - 98.3) < 0.5)
    }

    @Test func theManualOffsetAndTheDriftCorrectionAreSummed() async {
        // Sending either alone would silently discard the other.
        let engine = FakeVideoPlayerEngine()
        engine.videoFPS = 23.976
        let m = await atPosition(3600, engine: engine)
        m.setSubtitleSourceFPS(25)

        m.adjustSubtitleDelay(by: 2)

        #expect(abs((engine.subtitleDelays.last ?? 0) - 149.46) < 0.5)
    }

    @Test func turningTheCorrectionOffReturnsToTheManualOffsetAlone() async {
        let engine = FakeVideoPlayerEngine()
        engine.videoFPS = 23.976
        let m = await atPosition(3600, engine: engine)
        m.setSubtitleSourceFPS(25)
        m.adjustSubtitleDelay(by: 2)

        m.setSubtitleSourceFPS(nil)

        #expect(m.isCorrectingSubtitleDrift == false)
        #expect(engine.subtitleDelays.last == 2)
    }

    @Test func anUnreportedVideoRateFallsBackToTheRateThatMattersInPractice() async {
        // If VLCKit will not report the file's rate, refusing to correct helps nobody — every
        // release this matters for is a 23.976 encode, and the viewer can see the result.
        let engine = FakeVideoPlayerEngine()
        engine.videoFPS = nil
        let m = await atPosition(3600, engine: engine)

        m.setSubtitleSourceFPS(25)

        #expect(abs(m.subtitleDriftDelay - 147.46) < 0.5)
    }

    @Test func aSubtitleAlreadyOnTheFilesRateCorrectsNothing() async {
        let engine = FakeVideoPlayerEngine()
        engine.videoFPS = 25
        let m = await atPosition(3600, engine: engine)

        m.setSubtitleSourceFPS(25)

        #expect(m.subtitleDriftDelay == 0)
    }

    @Test func anEpisodeSwapClearsTheDriftCorrectionToo() async {
        let engine = FakeVideoPlayerEngine()
        engine.videoFPS = 23.976
        let m = PlayerModel(request: Fixture.showRequest(episodes: 3, playingEpisode: 1),
                            engine: engine,
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _ in },
                            subtitles: FakeSubtitleProvider())
        m.start()
        await m.waitForIdleForTesting()
        m.setSubtitleSourceFPS(25)

        m.play(Episode(season: 1, number: 2, source: Fixture.episodeSource("e2")))
        await m.waitForIdleForTesting()

        #expect(m.isCorrectingSubtitleDrift == false)
    }

    @Test func anEpisodeSwapClearsTheOffset() async {
        // The offset was dialled against ONE subtitle. Carried into the next episode it would
        // silently mistime a subtitle that was correct.
        let engine = FakeVideoPlayerEngine()
        let m = PlayerModel(request: Fixture.showRequest(episodes: 3, playingEpisode: 1),
                            engine: engine,
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _ in },
                            subtitles: FakeSubtitleProvider())
        m.start()
        await m.waitForIdleForTesting()
        m.adjustSubtitleDelay(by: 3)
        #expect(m.subtitleDelay == 3)

        m.play(Episode(season: 1, number: 2, source: Fixture.episodeSource("e2")))
        await m.waitForIdleForTesting()

        #expect(m.subtitleDelay == 0)
    }

    @Test func azeroOffsetIsNotReassertedForNothing() {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine: engine)

        m.refreshTracks()

        #expect(engine.subtitleDelays.isEmpty)
    }
}
