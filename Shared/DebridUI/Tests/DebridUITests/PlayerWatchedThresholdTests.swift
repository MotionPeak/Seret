import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// The player is the only thing that knows where a film's dialogue ends, so it is the only thing
/// that can say "this is over" at the right moment. Everything downstream — the watched tick, the
/// Continue Watching rail, the Letterboxd diary entry — hangs off the flag it reports.
///
/// Good Will Hunting was filed in the diary at 1:40 of 2:06.
@MainActor
@Suite struct PlayerWatchedThresholdTests {

    /// 126 minutes, the runtime that made this visible.
    private let feature: Double = 126 * 60

    private final class Recorder: @unchecked Sendable {
        var finishedFlags: [Bool] = []
    }

    private func model(_ recorder: Recorder, engine: FakeVideoPlayerEngine) -> PlayerModel {
        PlayerModel(request: Fixture.request(), engine: engine,
                    unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _, finished in
                        recorder.finishedFlags.append(finished)
                    },
                    subtitles: nil)
    }

    /// Drive one tick at `position` and wait for the write it queues.
    private func tick(at position: Double, contentEnd: Double? = nil) async -> Recorder {
        let recorder = Recorder()
        let engine = FakeVideoPlayerEngine()
        let m = model(recorder, engine: engine)
        m.start()
        await m.waitForIdleForTesting()
        m.contentEndTime = contentEnd
        engine.emit(.time(PlaybackTime(position: position, duration: feature)))
        await m.waitForIdleForTesting()
        await m.progressSaveTask?.value
        return recorder
    }

    @Test func fourFifthsOfTheWayInIsNotWatched() async {
        let r = await tick(at: 0.81 * feature)
        #expect(r.finishedFlags.last == false)
    }

    @Test func aFilmWithNoSubtitleIsWatchedOnceTheEstimateIsPassed() async {
        let r = await tick(at: 0.93 * feature)
        #expect(r.finishedFlags.last == true)
    }

    /// The whole point of asking the player: with a subtitle loaded, the last spoken line is the
    /// end of the film, and it lands EARLIER than the runtime estimate would.
    @Test func theEndOfTheDialogueIsWhatCountsWhenASubtitleIsLoaded() async {
        let dialogueEnd = 0.85 * feature
        let r = await tick(at: dialogueEnd + 1, contentEnd: dialogueEnd)
        #expect(r.finishedFlags.last == true)
    }

    /// ...and a tick before that line is still mid-film, even though it is past four fifths.
    @Test func aTickBeforeTheLastLineIsStillMidFilm() async {
        let dialogueEnd = 0.85 * feature
        let r = await tick(at: dialogueEnd - 1, contentEnd: dialogueEnd)
        #expect(r.finishedFlags.last == false)
    }
}
