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
