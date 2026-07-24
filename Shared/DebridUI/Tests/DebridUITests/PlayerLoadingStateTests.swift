import Testing
import Foundation
@testable import DebridUI
import DebridCore

@MainActor
@Suite struct PlayerLoadingStateTests {

    private func makeModel(request: PlaybackRequest = Fixture.request(),
                           engine: FakeVideoPlayerEngine) -> PlayerModel {
        PlayerModel(request: request, engine: engine,
                    unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _ in }, subtitles: nil)
    }

    @Test func pausedBeforePlayingClearsTheLoadingGate() async {
        // VLCKit can report .paused before it ever reports .playing (it renders the first frame
        // when it pauses). The overlay must not cover a video that is one play() away.
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine: engine)
        model.start()
        await model.waitForIdleForTesting()
        #expect(model.hasRenderedFrame == false)      // nothing has opened yet

        engine.emit(.state(.paused))
        await model.waitForIdleForTesting()

        #expect(model.hasRenderedFrame == true)
        #expect(model.isBuffering == false)
        #expect(model.phase == .paused)
    }

    @Test func pausedDuringAnEpisodeSwapDoesNotClearTheSwapGuard() async {
        // The OUTGOING media can emit a late .paused mid-swap. markRendered() also clears
        // `isSwitching`, which is what stops the old media's late .ended from auto-advancing
        // a second time — so a .paused while switching must NOT mark rendered.
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.showRequest(playingEpisode: 1), engine: engine)
        model.start()
        await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 5, duration: 100)))
        engine.emit(.time(.init(position: 6, duration: 100)))
        await model.waitForIdleForTesting()
        #expect(model.hasRenderedFrame == true)

        model.playNextNow()                            // begins a swap → isSwitching = true
        await model.waitForIdleForTesting()
        #expect(model.hasRenderedFrame == false)       // reload() reset it

        engine.emit(.state(.paused))                   // the OLD media's late event
        await model.waitForIdleForTesting()
        #expect(model.hasRenderedFrame == false)       // still guarded
    }

    @Test func aResumeSeekThatLandsShortStillClearsTheOverlay() async {
        // :input-fast-seek lands on the nearest keyframe, which can be far more than the 5s
        // arrival slack before the target. Arrival then never registers and the resume branch
        // returns on every tick forever — the loading overlay never clears. After a grace
        // period the model must accept the playhead where it actually is.
        let engine = FakeVideoPlayerEngine()
        let model = PlayerModel(request: Fixture.request(resumeAt: 600), engine: engine,
                                unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, _, _ in }, subtitles: nil)
        model.start()
        await model.waitForIdleForTesting()
        #expect(engine.seeks == [600])

        // Ticks start near zero → the deferred seek fires.
        engine.emit(.time(.init(position: 0.3, duration: 3600)))
        await model.waitForIdleForTesting()
        #expect(engine.seeks == [600, 600])

        // The seek lands at 570 — 30s short, outside the 5s slack. It advances normally from
        // there but can never satisfy `position >= 595`.
        for i in 0..<20 {
            engine.emit(.time(.init(position: 570 + Double(i) * 0.5, duration: 3600)))
            await model.waitForIdleForTesting()
        }

        #expect(model.hasRenderedFrame == true)     // grace expired → accepted, overlay cleared
        #expect(model.position > 570)               // and the bar tracks the real playhead
    }

    @Test func anEndBeforeAnyFrameIsAFailureNotAnEndOfFile() async {
        // VLCKit maps a failed open AND a real EOF to .stopped → .ended. Treating a failed open
        // as EOF records progress at 0 and silently binges forward to the next episode.
        let engine = FakeVideoPlayerEngine()
        var advancedTo: [String] = []
        let model = PlayerModel(request: Fixture.showRequest(playingEpisode: 1), engine: engine,
                                unrestrict: { link in advancedTo.append(link)
                                              return URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, _, _ in }, subtitles: nil)
        model.start()
        await model.waitForIdleForTesting()
        #expect(advancedTo == ["rd://e1"])

        engine.emit(.state(.ended))                    // never rendered, position still 0
        await model.waitForIdleForTesting()

        #expect(model.phase == .failed("The stream stopped before it started. The Real-Debrid link may have expired."))
        #expect(advancedTo == ["rd://e1"])             // did NOT auto-advance
        #expect(model.shouldDismiss == false)
    }

    @Test func anEndAfterRealPlaybackStillAdvances() async {
        let engine = FakeVideoPlayerEngine()
        var advancedTo: [String] = []
        let model = PlayerModel(request: Fixture.showRequest(playingEpisode: 1), engine: engine,
                                unrestrict: { link in advancedTo.append(link)
                                              return URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, _, _ in }, subtitles: nil)
        model.start()
        await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 100, duration: 120)))
        engine.emit(.time(.init(position: 119, duration: 120)))
        await model.waitForIdleForTesting()
        #expect(model.hasRenderedFrame == true)

        engine.emit(.state(.ended))
        await model.waitForIdleForTesting()

        #expect(advancedTo == ["rd://e1", "rd://e2"])  // real EOF → binge advance, unchanged
    }

    @Test func aLoadThatNeverRendersFailsAfterTheTimeout() async {
        let engine = FakeVideoPlayerEngine()
        let model = PlayerModel(request: Fixture.request(), engine: engine,
                                unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, _, _ in }, subtitles: nil,
                                loadTimeout: 0.1)
        model.start()
        await model.waitForIdleForTesting()
        #expect(model.phase == .preparing)

        try? await Task.sleep(for: .seconds(0.3))       // no frames ever arrive
        await model.waitForIdleForTesting()

        #expect(model.phase == .failed("This stream didn't start. The Real-Debrid link may have expired."))
    }

    @Test func aLoadThatRendersCancelsTheTimeout() async {
        let engine = FakeVideoPlayerEngine()
        let model = PlayerModel(request: Fixture.request(), engine: engine,
                                unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, _, _ in }, subtitles: nil,
                                loadTimeout: 0.1)
        model.start()
        await model.waitForIdleForTesting()
        engine.emit(.state(.playing))
        await model.waitForIdleForTesting()

        try? await Task.sleep(for: .seconds(0.3))
        await model.waitForIdleForTesting()

        #expect(model.phase == .playing)                // the watchdog was disarmed
    }

    @Test func anEpisodeAdvanceDoesNotTakeOverTheScreen() async {
        // reload() clears hasRenderedFrame, but the viewer is already watching — a binge advance
        // must show the bar's inline spinner, not a full-screen overlay.
        let engine = FakeVideoPlayerEngine()
        let model = PlayerModel(request: Fixture.showRequest(playingEpisode: 1), engine: engine,
                                unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, _, _ in }, subtitles: nil)
        model.start()
        await model.waitForIdleForTesting()
        #expect(model.isColdOpen == true)                 // first open: overlay is right

        engine.emit(.time(.init(position: 10, duration: 100)))
        engine.emit(.time(.init(position: 11, duration: 100)))
        await model.waitForIdleForTesting()
        #expect(model.isColdOpen == false)

        model.playNextNow()
        await model.waitForIdleForTesting()
        #expect(model.hasRenderedFrame == false)          // reloading…
        #expect(model.isColdOpen == false)                // …but NOT a cold open
    }
}
