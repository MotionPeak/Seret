import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// Seeking while paused, and coming back from it.
///
/// libvlc 4's paused seek is the broken path on the Apple TV (QA sweep 2026-10-20, §2d): every one
/// logged `reading while paused (buggy demux?)` and an input-control flood, and its clock came out
/// wrong — resuming after one, libvlc took every picture for 15 s late and dropped 390 in 150 ms.
/// So a paused burst reaches the engine as one seek, and Play re-seeks once it is playing.
@MainActor
@Suite struct PlayerPausedSeekTests {

    private func makeModel(_ engine: FakeVideoPlayerEngine, window: Double = 0.05,
                           stallThreshold: Double = 2.5,
                           resume: Double? = nil) -> PlayerModel {
        PlayerModel(request: Fixture.request(), engine: engine,
                    unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _, _ in }, subtitles: nil,
                    resolveResume: resume.map { r in { (_: String) async -> Double? in r } },
                    seekCoalesceWindow: window, stallThreshold: stallThreshold)
    }

    /// Playing at `position`, then paused.
    private func pausedAt(_ position: Double, _ model: PlayerModel,
                          _ engine: FakeVideoPlayerEngine) async {
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: position, duration: 3600)))
        engine.emit(.time(.init(position: position + 0.5, duration: 3600)))
        engine.emit(.state(.paused))
        await model.waitForIdleForTesting()
    }

    @Test func aPausedBurstReachesTheEngineAsOneSeek() async throws {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine, window: 0.15)
        await pausedAt(100, model, engine)
        let before = engine.seeks.count

        model.skip(10); model.skip(10); model.skip(10)
        #expect(engine.seeks.count == before, "a paused tap seeks at once: \(engine.seeks)")
        #expect(model.position == 130.5)

        try await Task.sleep(for: .milliseconds(400))      // the window closes
        #expect(Array(engine.seeks.dropFirst(before)) == [130.5])
        #expect(model.pausedSeekSent)
        await model.teardown()
    }

    @Test func playAfterAPausedSeekPlaysThenSeeksToTheBar() async throws {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine)
        await pausedAt(100, model, engine)
        model.skip(-10)
        try await Task.sleep(for: .milliseconds(200))      // the paused seek lands on the engine
        let mark = engine.transport.count

        model.togglePlayPause()

        #expect(Array(engine.transport.dropFirst(mark)) == ["play", "seek 90"])
        #expect(model.position == 90.5)
        #expect(model.pausedSeekSent == false)
        await model.teardown()
    }

    /// Play inside the window: the pending target IS the resume seek — no second one after it.
    @Test func playInsideTheWindowFoldsThePendingTargetIntoTheResumeSeek() async throws {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine, window: 0.3)
        await pausedAt(100, model, engine)
        let mark = engine.transport.count

        model.skip(10); model.skip(10)
        model.play()
        try await Task.sleep(for: .milliseconds(500))      // past where the window would close

        #expect(Array(engine.transport.dropFirst(mark)) == ["play", "seek 120"])
        await model.teardown()
    }

    /// No seek while paused: Play is just play, as it always was.
    @Test func playWithoutAPausedSeekIsAPlainPlay() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine)
        await pausedAt(100, model, engine)
        let mark = engine.transport.count

        model.togglePlayPause()

        #expect(Array(engine.transport.dropFirst(mark)) == ["play"])
        await model.teardown()
    }

    /// Playing, a tap still seeks at once — the coalescer's leading seek is untouched.
    @Test func aPlayingTapStillSeeksAtOnce() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine, window: 0.3)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: 100, duration: 3600)))
        engine.emit(.time(.init(position: 100.5, duration: 3600)))
        await model.waitForIdleForTesting()

        model.skip(10)
        #expect(engine.seeks.last == 110.5)
        #expect(model.pausedSeekSent == false)
        await model.teardown()
    }

    // MARK: - Resume and spinner bookkeeping (D13)

    /// VLCKit echoes the pre-seek time after `setTime:`. Right after the load's early resume seek
    /// that echo reads ~0, and it used to fire the deferred seek: the same seek, twice.
    @Test func theEchoOfTheEarlyResumeSeekDoesNotSeekAgain() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine, resume: 600)
        model.start(); await model.waitForIdleForTesting()
        #expect(engine.seeks == [600])

        engine.emit(.time(.init(position: 0, duration: 0)))       // the echo
        await model.waitForIdleForTesting()
        #expect(engine.seeks == [600], "the echo re-seeked: \(engine.seeks)")

        // …but a seek that really was dropped — the film running from the top — still gets its
        // deferred seek.
        engine.emit(.time(.init(position: 2, duration: 3600)))
        await model.waitForIdleForTesting()
        #expect(engine.seeks == [600, 600])
        await model.teardown()
    }

    /// The landing tick sits at the target, so it never counted as "advance" and the stall clock
    /// kept the stamp from before the seek: a seek slower than the threshold flashed the spinner
    /// back up the moment it landed.
    @Test func aLandedSeekRestartsTheStallClock() async throws {
        let engine = FakeVideoPlayerEngine()
        // Wide margins: a loaded CI box must not be able to make the landing look late.
        let model = makeModel(engine, stallThreshold: 3.0)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: 100, duration: 3600)))
        engine.emit(.time(.init(position: 100.5, duration: 3600)))
        await model.waitForIdleForTesting()

        model.skip(30)
        try await Task.sleep(for: .milliseconds(3300))     // a seek slower than the threshold
        engine.emit(.time(.init(position: 130.5, duration: 3600)))   // lands
        await model.waitForIdleForTesting()
        #expect(model.isBuffering == false)

        try await Task.sleep(for: .seconds(1))             // well under the threshold since it landed
        #expect(model.isBuffering == false, "the spinner came back over a seek that had landed")
        await model.teardown()
    }
}
