import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// A PAUSED player must never claim to be loading.
///
/// Two paths used to raise the hint without asking whether we were paused, and a paused player
/// never emits `.playing`, so nothing came along to lower it again — the spinner simply stuck.
/// This got worse once scrubbing was gated on being paused, because that made "seek while paused"
/// the normal way to move around a film rather than an edge case.
@MainActor
@Suite struct PlayerPausedBufferingTests {

    private func makeModel(engine: FakeVideoPlayerEngine) -> PlayerModel {
        PlayerModel(request: Fixture.request(), engine: engine,
                    unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _ in }, subtitles: nil,
                    seekCoalesceWindow: 0.05)
    }

    private func warmUpAndPause(_ model: PlayerModel, _ engine: FakeVideoPlayerEngine) async {
        model.start()
        await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 100, duration: 3600)))
        engine.emit(.time(.init(position: 100.5, duration: 3600)))
        await model.waitForIdleForTesting()
        engine.emit(.state(.paused))
        await model.waitForIdleForTesting()
    }

    /// VLCKit emits `.buffering` spuriously, including while paused. That must not light the hint.
    @Test func aSpuriousBufferingEventWhilePausedDoesNotShowLoading() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine: engine)
        await warmUpAndPause(model, engine)
        #expect(model.phase == .paused)
        #expect(model.isBuffering == false)

        engine.emit(.state(.buffering))
        await model.waitForIdleForTesting()

        #expect(model.phase == .paused, "a stray buffering event must not knock us out of paused")
        #expect(model.isBuffering == false, "a paused player is not loading")
    }

    /// Skipping while paused is now the normal way to move around — it must not strand the hint.
    @Test func skippingWhilePausedDoesNotShowLoading() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine: engine)
        await warmUpAndPause(model, engine)

        model.skip(30)
        await model.waitForIdleForTesting()

        #expect(model.isBuffering == false, "a paused seek has no frames to wait for")
    }

    /// The guard must not break the real case: while PLAYING, a seek still shows the hint.
    @Test func skippingWhilePlayingStillShowsLoading() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine: engine)
        model.start()
        await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 100, duration: 3600)))
        engine.emit(.time(.init(position: 100.5, duration: 3600)))
        await model.waitForIdleForTesting()
        #expect(model.isBuffering == false)

        model.skip(30)
        await model.waitForIdleForTesting()

        #expect(model.isBuffering == true, "a playing seek genuinely waits on frames")
    }
}
