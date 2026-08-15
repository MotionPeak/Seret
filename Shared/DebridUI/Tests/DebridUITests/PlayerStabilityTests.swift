import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// Defects found by the 2026-08 stability sweep. Each test here was run against the unfixed code
/// first and observed to fail — the comment on each one says what it looked like to a viewer.
@MainActor
@Suite struct PlayerStabilityTests {

    /// Collects what the model asked to be persisted, so a test can assert on the sequence rather
    /// than on "it didn't crash".
    @MainActor final class ProgressRecorder {
        private(set) var positions: [Double] = []
        func record(_ position: Double) { positions.append(position) }
    }

    private func warmUp(_ model: PlayerModel, _ engine: FakeVideoPlayerEngine,
                        to position: Double, duration: Double = 3600) async {
        model.start()
        await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: position, duration: duration)))
        engine.emit(.time(.init(position: position + 0.5, duration: duration)))
        await model.waitForIdleForTesting()
    }

    // MARK: - End of file

    /// VLCKit reports the end of a file TWICE — it emits `.stopping` and then `.stopped`, and the
    /// engine folds both into `.ended`. `handle(state:)` spawns an unstructured Task per event, and
    /// `finish()` read its guards before awaiting the progress write, so both tasks got past the
    /// guards. The first advanced to E2 and the second, resuming afterwards, read the now-current
    /// episode and advanced again: the viewer finished E1 and landed on E3.
    @Test func twoEndOfFileEventsAdvanceExactlyOneEpisode() async {
        let engine = FakeVideoPlayerEngine()
        let model = PlayerModel(request: Fixture.showRequest(episodes: 3, playingEpisode: 1),
                                engine: engine,
                                unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, _, _ in }, subtitles: nil,
                                // Stands in for the real stop hook: a Trakt scrobble-stop plus a
                                // full re-sync, i.e. a guaranteed suspension point.
                                onScrobbleStop: { _ in try? await Task.sleep(for: .seconds(0.05)) })
        await warmUp(model, engine, to: 100, duration: 200)

        engine.emit(.state(.ended))          // .stopping
        engine.emit(.state(.ended))          // …and .stopped
        try? await Task.sleep(for: .seconds(0.35))

        #expect(model.currentEpisode?.number == 2)
    }

    // MARK: - Leaving the player

    /// `teardown()` awaited the Trakt stop-scrobble and a full library re-sync BEFORE telling the
    /// engine to stop, so pressing Menu left the film's audio playing over the Detail page for as
    /// long as those calls took — seconds on a weak connection, and up to URLSession's 60s timeout
    /// on a stalled socket.
    @Test func leavingThePlayerStopsTheEngineBeforeTheNetworkWrite() async {
        let engine = FakeVideoPlayerEngine()
        let model = PlayerModel(request: Fixture.request(), engine: engine,
                                unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, _, _ in }, subtitles: nil,
                                onScrobbleStop: { _ in try? await Task.sleep(for: .seconds(0.3)) })
        await warmUp(model, engine, to: 100)

        let teardown = Task { await model.teardown() }
        try? await Task.sleep(for: .seconds(0.06))   // still inside the write

        #expect(engine.stopCalled == true)           // …but the sound is already gone
        await teardown.value
    }

    // MARK: - Progress

    /// The save gate was `position - lastSavedPosition >= saveInterval`, which is only ever true
    /// going forward. Rewind twenty minutes and nothing was written again until the playhead had
    /// climbed all the way back — so leaving after a rewind resumed at the point you rewound FROM.
    @Test func progressKeepsSavingAfterARewind() async {
        let engine = FakeVideoPlayerEngine()
        let recorder = ProgressRecorder()
        let model = PlayerModel(request: Fixture.request(), engine: engine,
                                unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, position, _ in recorder.record(position) },
                                subtitles: nil)
        await warmUp(model, engine, to: 1000)
        await model.waitForIdleForTesting()
        #expect(recorder.positions.contains { $0 >= 1000 })

        // Rewind: the engine reports the new, EARLIER playhead.
        engine.emit(.time(.init(position: 400, duration: 3600)))
        engine.emit(.time(.init(position: 401, duration: 3600)))
        await model.waitForIdleForTesting()

        #expect(recorder.positions.contains { $0 < 500 })
    }

    /// The progress write is awaited from `tick()`, which runs inside the single event-consumption
    /// loop — so a Trakt heartbeat (a real HTTP POST, and right now one that 401s after a full
    /// round-trip) stalled every time update and state change behind it. The scrub bar froze and
    /// the transport stopped answering for the length of the request.
    @Test func aSlowProgressWriteDoesNotStallTheEventLoop() async {
        let engine = FakeVideoPlayerEngine()
        let model = PlayerModel(request: Fixture.request(), engine: engine,
                                unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, _, _ in
                                    try? await Task.sleep(for: .seconds(0.3))
                                },
                                subtitles: nil)
        await warmUp(model, engine, to: 100)

        engine.emit(.time(.init(position: 200, duration: 3600)))   // triggers a (slow) save
        engine.emit(.time(.init(position: 201, duration: 3600)))   // must still be processed
        try? await Task.sleep(for: .seconds(0.1))                  // …well before the write returns

        #expect(model.position == 201)
    }

    // MARK: - Seeking

    /// `pendingSeek` holds the displayed playhead at the optimistic target and drops VLCKit's stale
    /// pre-seek echoes until one lands nearer the target. If the engine DROPS the seek — which it
    /// does on an unseekable stretch or a stalled socket — no tick ever lands, so the bar froze, the
    /// spinner stuck, and progress stopped being written for the rest of the film.
    @Test func aDroppedSeekDoesNotFreezeTheBarForever() async {
        let engine = FakeVideoPlayerEngine()
        let model = PlayerModel(request: Fixture.request(), engine: engine,
                                unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, _, _ in }, subtitles: nil)
        await warmUp(model, engine, to: 100)

        model.skip(600)                        // the engine will simply never honour it
        #expect(model.position == 700.5)

        // Playback carries on where it was; every one of these is nearer the ORIGIN than the target.
        for i in 1...20 {
            engine.emit(.time(.init(position: 100.5 + Double(i), duration: 3600)))
        }
        await model.waitForIdleForTesting()

        #expect(model.position > 100, "the bar must track the real playhead again")
        #expect(model.position < 200, "…and not stay stuck at the target that never landed")
        #expect(model.isBuffering == false)
    }

    /// A fractional (Trakt) resume is stashed at load and converted to a seek target on the first
    /// tick that reports a duration. `handleUserSeek` superseded `resumeTarget` but not
    /// `resumeFraction`, so skipping during the cold open was silently undone a tick later — the
    /// viewer skipped forward and got yanked back to the resume point.
    @Test func aSeekDuringTheColdOpenIsNotUndoneByAFractionalResume() async {
        let engine = FakeVideoPlayerEngine()
        let model = PlayerModel(request: Fixture.request(), engine: engine,
                                unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, _, _ in }, subtitles: nil,
                                resolveResumeFraction: { _ in 0.5 })
        model.start()
        await model.waitForIdleForTesting()     // resumeFraction is armed, duration still unknown

        model.skip(30)                          // the viewer skips before the first frame
        engine.emit(.time(.init(position: 30, duration: 3600)))
        await model.waitForIdleForTesting()

        #expect(model.resumeTarget == 0, "the stashed fraction must not re-arm a resume seek")
    }

    // MARK: - Up Next

    /// The countdown ran on its own timer with no further reference to playback state. Pausing on
    /// the Up Next bar — to read the next episode's title, or to answer the door — did not hold it:
    /// it reached zero and started the next episode over the viewer's paused frame.
    @Test func theUpNextCountdownHoldsWhilePaused() async {
        let engine = FakeVideoPlayerEngine()
        let model = PlayerModel(request: Fixture.showRequest(playingEpisode: 1), engine: engine,
                                unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, _, _ in }, subtitles: nil)
        model.start()
        await model.waitForIdleForTesting()
        // Cross the Up Next threshold on a short file so the bar appears.
        engine.emit(.time(.init(position: 60, duration: 100)))
        engine.emit(.time(.init(position: 75, duration: 100)))
        await model.waitForIdleForTesting()
        #expect(model.upNextVisible == true)
        let remaining = model.upNextSecondsRemaining

        engine.emit(.state(.paused))                  // the viewer holds it
        await model.waitForIdleForTesting()
        try? await Task.sleep(for: .seconds(2.2))

        #expect(model.upNextSecondsRemaining == remaining)
        #expect(model.currentEpisode?.number == 1)    // …and it did not advance
    }

    // MARK: - Track selection across a version switch

    /// libvlc's track ids are positional ("audio/0", "spu/0") and therefore collide between two
    /// releases of the same title. `reload()` reset every other selection latch but left the two
    /// mirrored ids, so after "Try another version" the preference matcher compared the new track
    /// against the OLD id, found them equal and never told the engine — the replacement played with
    /// subtitles off while the panel still showed them ticked.
    @Test func tryingAnotherVersionReselectsTracksDespiteCollidingIDs() async {
        let engine = FakeVideoPlayerEngine()
        let prefs = FakeTrackPreferences()
        prefs.record(subtitle: .language("he"), forTitle: "m1")
        let sources = [Fixture.movieSource("rd://a"), Fixture.movieSource("rd://b")]
        let model = PlayerModel(request: Fixture.request(sources: sources), engine: engine,
                                unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, _, _ in }, subtitles: nil,
                                trackPreferences: prefs)
        engine.subtitleTracks = [MediaTrack(id: "spu/0", kind: .subtitle, name: "Hebrew", language: "he")]
        await warmUp(model, engine, to: 10)
        model.refreshTracks()
        #expect(model.selectedSubtitleID == "spu/0")

        model.tryAnotherVersion()                    // the replacement's Hebrew track is ALSO spu/0
        await model.waitForIdleForTesting()
        engine.clearSubtitleSelection()
        model.refreshTracks()

        #expect(engine.selectedSubtitleID == "spu/0", "the new media must actually be told")
    }
}
