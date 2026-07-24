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
}
