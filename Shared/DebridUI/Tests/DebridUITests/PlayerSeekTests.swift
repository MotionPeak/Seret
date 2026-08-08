import Testing
import Foundation
@testable import DebridUI
import DebridCore

@MainActor
@Suite struct PlayerSeekTests {

    private func makeModel(engine: FakeVideoPlayerEngine,
                           seekCoalesceWindow: Double = 0.05,
                           scanInterval: Double = 0.5,
                           scanSeekInterval: Double = 1.5,
                           scanMaxDuration: Double = 15) -> PlayerModel {
        PlayerModel(request: Fixture.request(), engine: engine,
                    unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _ in }, subtitles: nil,
                    seekCoalesceWindow: seekCoalesceWindow,
                    scanInterval: scanInterval, scanSeekInterval: scanSeekInterval,
                    scanMaxDuration: scanMaxDuration)
    }

    /// Bring the model to a live, rendered, playing state at `position`.
    private func warmUp(_ model: PlayerModel, _ engine: FakeVideoPlayerEngine,
                        to position: Double, duration: Double = 3600) async {
        model.start()
        await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: position, duration: duration)))
        engine.emit(.time(.init(position: position + 0.5, duration: duration)))
        await model.waitForIdleForTesting()
    }

    @Test func aLandedSeekClearsTheBufferingHint() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine: engine)
        await warmUp(model, engine, to: 100)
        #expect(model.isBuffering == false)

        model.skip(30)
        #expect(model.isBuffering == true)             // optimistic: show the hint while it rebuffers

        // A stale pre-seek echo must not clear it…
        engine.emit(.time(.init(position: 100.6, duration: 3600)))
        await model.waitForIdleForTesting()
        #expect(model.isBuffering == true)

        // …but the landing tick must.
        engine.emit(.time(.init(position: 130.4, duration: 3600)))
        await model.waitForIdleForTesting()
        #expect(model.isBuffering == false)
    }

    @Test func aCancelledCoalescerDoesNotClearItsSuccessor() async {
        // cancelCoalescedSeek() cancels the in-flight window task, but that task's cleanup runs
        // LATER — at the next suspension point. It used to null `seekDispatchTask`
        // unconditionally, so it wiped the registration of a window opened in between. The next
        // skip then saw an empty slot, opened a second window and issued an extra engine seek
        // instead of merely retargeting the open one.
        //
        // Reproducing it needs a real suspension between opening window B and the next skip, so
        // the cancelled window A's cleanup can interleave.
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine: engine, seekCoalesceWindow: 0.5)
        await warmUp(model, engine, to: 100)            // playhead at 100.5

        model.skip(10)                                  // window A opens, leading seek → 110.5
        model.commitScrubForTesting(to: 500)            // cancels A, direct seek → 500
        model.skip(10)                                  // window B opens, leading seek → 510

        await Task.yield()                              // ← A's cleanup runs here
        await Task.yield()

        let seeksBefore = engine.seeks.count             // 3: A leading, the commit, B leading
        model.skip(30)                                  // inside B's window → RETARGET ONLY

        // THE ASSERTION THAT MATTERS. Window B is still open, so this skip must not reach the
        // engine at all — coalescing is the whole point. With the race, A's stale cleanup had
        // already emptied the slot, so this opened a fresh window and seeked immediately, which
        // is exactly the eager-seek behaviour that makes a skip burst rebuffer repeatedly.
        #expect(engine.seeks.count == seeksBefore)

        try? await Task.sleep(for: .seconds(0.9))       // let the window close
        await model.waitForIdleForTesting()
        #expect(engine.seeks == [110.5, 500, 510, 540]) // one trailing seek at the final target
    }

    @Test func holdingToScanRepeatedlySkipsAndAccelerates() async {
        // Hold-to-scan is implemented as accelerating repeated SKIPS, not a negative playback
        // rate: libvlc has no reliable reverse playback, so a negative rate would simply do
        // nothing backwards. Repeated seeks behave identically in both directions.
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine: engine, seekCoalesceWindow: 0.01, scanInterval: 0.2,
                              scanSeekInterval: 0.4)
        await warmUp(model, engine, to: 1000)

        model.beginScan(direction: 1)
        try? await Task.sleep(for: .seconds(1.4))
        #expect(model.position > 1000)             // it kept going while held, and moved forward
        model.endScan()

        let afterRelease = engine.seeks.count
        try? await Task.sleep(for: .seconds(0.8))
        #expect(engine.seeks.count == afterRelease) // release stops it
    }

    @Test func scanningBackwardMovesBackward() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine: engine, seekCoalesceWindow: 0.01)
        await warmUp(model, engine, to: 1000)

        model.beginScan(direction: -1)
        try? await Task.sleep(for: .seconds(1.4))
        model.endScan()

        #expect(model.position < 1000)
    }

    // MARK: - The hold must not hammer libvlc

    /// A held scan repeats every `scanInterval` (0.5s in production), and it USED to hand every
    /// single repeat to the engine. Each of those is a full network seek + re-fill — and on tvOS the
    /// pipeline pre-roll is 2s, so libvlc was told to restart a 2s fill four times a second and never
    /// finished one. Setting `VLCMediaPlayer.time` blocks the main thread while the demuxer moves, so
    /// the whole UI — including the remote — went unresponsive for as long as the hold lasted. That
    /// is the owner's "it keeps forwarding and won't let me exit until a couple of seconds later".
    ///
    /// The displayed playhead still moves on every repeat; only the ENGINE is throttled.
    @Test func aHeldScanThrottlesTheEngineWhileTheBarKeepsMoving() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine: engine, seekCoalesceWindow: 0.01,
                              scanInterval: 0.05, scanSeekInterval: 0.5)
        await warmUp(model, engine, to: 1000)
        let before = engine.seeks.count

        model.beginScan(direction: 1)
        try? await Task.sleep(for: .seconds(0.55))     // ~11 repeats
        let seeksDuring = engine.seeks.count - before
        let travelled = model.position - 1000.5
        model.endScan()

        #expect(travelled > 60)      // the bar travelled through many repeats…
        #expect(seeksDuring <= 3)    // …on no more than a seek every ~0.5s
    }

    /// Releasing must land the final target AT ONCE. Throttling the engine means the last repeats
    /// only moved the displayed playhead, so without an explicit flush on release the picture would
    /// stay wherever the last throttled seek left it — the bar and the film disagreeing.
    @Test func releasingAScanLandsTheFinalTargetImmediately() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine: engine, seekCoalesceWindow: 5,
                              scanInterval: 0.05, scanSeekInterval: 5)
        await warmUp(model, engine, to: 1000)

        model.beginScan(direction: 1)
        try? await Task.sleep(for: .seconds(0.35))
        model.endScan()

        #expect(engine.seeks.last == model.position)   // no waiting out a coalescing window
    }

    /// `isScanning` is what lets everything else — a play/pause press, Menu — know to call it off.
    @Test func isScanningTracksTheHold() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine: engine, scanInterval: 0.05, scanMaxDuration: 10)
        await warmUp(model, engine, to: 1000)

        #expect(model.isScanning == false)
        model.beginScan(direction: 1)
        #expect(model.isScanning == true)
        model.endScan()
        #expect(model.isScanning == false)
    }

    /// …and a scan that runs itself down must clear the flag too, or every later Menu press would be
    /// swallowed as "stop the scan" and the viewer could never leave the player.
    @Test func aSelfTerminatingScanClearsIsScanning() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine: engine, seekCoalesceWindow: 0.01,
                              scanInterval: 0.02, scanSeekInterval: 0.02, scanMaxDuration: 0.1)
        await warmUp(model, engine, to: 100)

        model.beginScan(direction: 1)          // …and deliberately never release
        try? await Task.sleep(for: .seconds(0.4))

        #expect(model.isScanning == false)
    }

    // MARK: - Runaway-scan guards

    /// The step must plateau. It used to grow ×1.6 with a 120s ceiling, so a few seconds of holding
    /// threw the film minutes ahead and kept accelerating — the reported "forwards uncontrollably".
    @Test func scanStepAcceleratesThenPlateaus() {
        #expect(PlayerModel.scanStep(atTick: 0) == 10)
        #expect(PlayerModel.scanStep(atTick: 1) == 15)
        #expect(PlayerModel.scanStep(atTick: 2) == 22.5)
        #expect(PlayerModel.scanStep(atTick: 5) == PlayerModel.scanMaxStep)   // capped by here…
        #expect(PlayerModel.scanStep(atTick: 500) == PlayerModel.scanMaxStep) // …and stays capped
    }

    /// Ten seconds of holding must stay in "fast-forward" territory rather than consuming the film.
    @Test func aTenSecondHoldTravelsAPlausibleDistance() {
        let ticks = Int(10 / 0.5)
        let travelled = (0..<ticks).reduce(0.0) { $0 + PlayerModel.scanStep(atTick: $1) }
        #expect(travelled < 600)   // under ten minutes of film for ten seconds of holding
    }

    /// Defence in depth for a LOST release event. `PlayerInputSurface` now ends a scan when it
    /// hands the remote to an overlay, but if a release ever goes missing again the loop must run
    /// down on its own instead of skipping until the film ends.
    @Test func scanStopsItselfWhenTheReleaseNeverArrives() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine: engine, seekCoalesceWindow: 0.01,
                              scanInterval: 0.02, scanMaxDuration: 0.1)
        await warmUp(model, engine, to: 100)

        model.beginScan(direction: 1)          // …and deliberately never call endScan()
        try? await Task.sleep(for: .seconds(0.4))
        let settled = model.position
        try? await Task.sleep(for: .seconds(0.3))

        #expect(model.position == settled)     // it stopped moving on its own
        #expect(model.scanTask == nil)         // …and tidied itself up
    }

    /// The self-terminating scan must not tidy up a LIVE successor: a viewer who releases and
    /// immediately re-holds keeps scanning.
    @Test func aSelfTerminatingScanDoesNotKillTheNextOne() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine: engine, seekCoalesceWindow: 0.01,
                              scanInterval: 0.02, scanMaxDuration: 0.06)
        await warmUp(model, engine, to: 100)

        model.beginScan(direction: 1)
        try? await Task.sleep(for: .seconds(0.05))
        model.beginScan(direction: 1)          // re-hold while the first is expiring
        try? await Task.sleep(for: .seconds(0.03))

        #expect(model.scanTask != nil)         // the successor is still running
        model.endScan()
    }
}
