import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// The saved resume point is the one piece of player state a viewer cannot recreate. These pin the
/// ways a session used to write over it with a place the viewer never reached — and the ways a
/// stream that merely stumbled was treated as a film that had ended.
@MainActor
@Suite struct PlayerResumeSafetyTests {

    /// The watch store as the player sees it: what `resolveResume` reads and `recordProgress`
    /// writes, so a write is visible to the next read exactly as on the device.
    @MainActor final class Store {
        var saved: [String: Double] = [:]
        private(set) var writes: [(key: String, position: Double)] = []
        func record(_ key: String, _ position: Double) {
            writes.append((key, position))
            saved[key] = position
        }
        func positions(_ key: String) -> [Double] { writes.filter { $0.key == key }.map(\.position) }
    }

    /// Holds the unrestrict open so the window before the engine has the media stays wide.
    actor Gate {
        private var closed = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func close() { closed = true }
        func open() {
            closed = false
            for w in waiters { w.resume() }
            waiters = []
        }
        func waitIfClosed() async {
            guard closed else { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    private func makeModel(request: PlaybackRequest = Fixture.request(),
                           engine: FakeVideoPlayerEngine, store: Store,
                           gate: Gate? = nil) -> PlayerModel {
        PlayerModel(request: request, engine: engine,
                    unrestrict: { _ in
                        await gate?.waitIfClosed()
                        return URL(string: "https://cdn/x.mkv")!
                    },
                    recordProgress: { key, _, position, _, _ in
                        await MainActor.run { store.record(key, position) }
                    },
                    subtitles: nil,
                    resolveResume: { key in await MainActor.run { store.saved[key] } })
    }

    private func playTo(_ position: Double, duration: Double, _ model: PlayerModel,
                        _ engine: FakeVideoPlayerEngine) async {
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: position - 1, duration: duration)))
        engine.emit(.time(.init(position: position, duration: duration)))
        await model.waitForIdleForTesting()
    }

    // MARK: - The resume window

    /// Resume at 1:00:00, early seek dropped, viewer backs out while it still says "Buffering…".
    /// `position` was still 0 there, and teardown wrote 0 over 1:00:00 — the next visit said "Play".
    @Test func leavingBeforeTheResumeLandsKeepsTheSavedPosition() async {
        let engine = FakeVideoPlayerEngine(), store = Store()
        store.saved["m1"] = 3600
        let model = makeModel(engine: engine, store: store)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 0.4, duration: 7200))); await model.waitForIdleForTesting()
        await model.teardown()
        #expect(store.positions("m1").allSatisfy { $0 >= 3600 })
        #expect(store.saved["m1"] == 3600)
    }

    /// A right-click while the resume is still travelling counted from 0: the film opened at 0:10
    /// and 0:10 replaced the saved place a second later.
    @Test func aSkipBeforeTheResumeLandsCountsFromTheResumePoint() async {
        let engine = FakeVideoPlayerEngine(), store = Store()
        store.saved["m1"] = 3600
        let model = makeModel(engine: engine, store: store)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 0.4, duration: 7200))); await model.waitForIdleForTesting()
        model.skip(10)
        #expect(engine.seeks.last == 3610)
        #expect(model.position == 3610)
    }

    /// The same press while the link is still being opened: the engine has no media to seek yet,
    /// so the skip has to move the place the load will seek to — not vanish and start at 0.
    @Test func aSkipWhileTheLinkIsStillOpeningMovesTheResumePoint() async {
        let engine = FakeVideoPlayerEngine(), store = Store(), gate = Gate()
        store.saved["m1"] = 3600
        await gate.close()
        let model = makeModel(engine: engine, store: store, gate: gate)
        model.start(); await model.waitForIdleWhileLoadIsHeldForTesting()
        for _ in 0..<2_000 where model.position != 3600 { await Task.yield() }
        #expect(model.position == 3600)                 // the bar shows where it will resume
        model.skip(10)
        await gate.open(); await model.waitForIdleForTesting()
        #expect(engine.seeks == [3610])
    }

    /// Picking another episode while this one's resume is still travelling filed 0 under it.
    @Test func swappingEpisodesBeforeTheResumeLandsKeepsTheOutgoingPlace() async {
        let request = Fixture.showRequest(episodes: 3, playingEpisode: 1)
        let e1 = request.contentKey
        let engine = FakeVideoPlayerEngine(), store = Store()
        store.saved[e1] = 600
        let model = makeModel(request: request, engine: engine, store: store)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 0.4, duration: 1800))); await model.waitForIdleForTesting()
        model.playNext(); await model.waitForIdleForTesting()
        #expect(store.positions(e1).allSatisfy { $0 >= 600 })
        #expect(store.saved[e1] == 600)
    }

    /// The tick that lands the resume used to return before publishing it.
    @Test func theArrivalTickShowsTheRealPlayhead() async {
        let engine = FakeVideoPlayerEngine(), store = Store()
        store.saved["m1"] = 3600
        let model = makeModel(engine: engine, store: store)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 3601, duration: 7200))); await model.waitForIdleForTesting()
        #expect(model.position == 3601)
    }

    /// A saved place past THIS version's length: the early seek (issued before the length is known)
    /// landed at the very end, and the title was then recorded as finished.
    @Test func aResumePointPastThisVersionsEndStartsFromTheTop() async {
        let engine = FakeVideoPlayerEngine(), store = Store()
        store.saved["m1"] = 7000
        let model = makeModel(engine: engine, store: store)
        model.start(); await model.waitForIdleForTesting()
        #expect(engine.seeks == [7000])
        engine.emit(.time(.init(position: 6490, duration: 6500))); await model.waitForIdleForTesting()
        #expect(engine.seeks == [7000, 0])
    }

    // MARK: - Retry

    /// "From Start", then the stream fails at 40 minutes and Retry starts over from 0:00 — and the
    /// first tick replaced 40:00. `fromStart` describes how the session BEGAN, not every reload.
    @Test func retryAfterStartingOverResumesWhereItFailed() async throws {
        let engine = FakeVideoPlayerEngine(), store = Store()
        store.saved["m1"] = 4000                         // the place before "From Start"
        let model = makeModel(request: Fixture.request(fromStart: true), engine: engine, store: store)
        model.start(); await model.waitForIdleForTesting()
        #expect(engine.seeks.isEmpty)                    // From Start really is from the start
        await playTo(2400, duration: 6000, model, engine)
        let failedAt = try #require(store.saved["m1"])
        #expect(failedAt >= 2399 && failedAt <= 2400)    // the new session owns the place now
        engine.emit(.state(.failed("boom"))); await model.waitForIdleForTesting()
        model.retry(); await model.waitForIdleForTesting()
        #expect(engine.seeks == [failedAt])
    }

    /// Play/Pause on the failure screen called `engine.play()` on the dead media: libvlc reopened
    /// it from 0, the error overlay vanished, and ticks overwrote the saved place.
    @Test func playPauseOnTheFailureScreenRetriesAtTheSavedPlace() async {
        let engine = FakeVideoPlayerEngine(), store = Store()
        let model = makeModel(engine: engine, store: store)
        model.start(); await model.waitForIdleForTesting()
        await playTo(101, duration: 6000, model, engine)
        engine.emit(.state(.failed("Real-Debrid stopped sending this file."))); await model.waitForIdleForTesting()
        let saved = store.saved["m1"]
        model.togglePlayPause(); await model.waitForIdleForTesting()
        #expect(engine.loadCount == 2)                   // a real retry…
        #expect(engine.seeks == [saved ?? -1])           // …that resumes where it failed
    }

    /// `reload()` closes the old stream, and the dying open reports `.failed` / `.ended` while the
    /// new link is still resolving. They described the OLD media: the error came back mid-retry,
    /// and the latched end left the retried film unable to end at all.
    @Test func theOutgoingMediasDeathDuringARetryIsNotTheNewOnes() async {
        let engine = FakeVideoPlayerEngine(), store = Store(), gate = Gate()
        let model = makeModel(engine: engine, store: store, gate: gate)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.failed("This stream didn't start."))); await model.waitForIdleForTesting()
        await gate.close()
        model.retry(); await model.waitForIdleWhileLoadIsHeldForTesting()
        engine.emit(.state(.failed("Playback failed.")))
        engine.emit(.state(.ended)); await model.waitForIdleWhileLoadIsHeldForTesting()
        #expect(!model.phase.isFailed)
        await gate.open(); await model.waitForIdleForTesting()
        await playTo(99, duration: 100, model, engine)
        engine.emit(.state(.ended)); await model.waitForIdleForTesting()
        #expect(model.shouldDismiss)                     // the real end still ends it
    }

    // MARK: - An end that is not the end

    /// libvlc reports a dropped connection as the end of the file. Forty minutes into a two-hour
    /// film that is not the end: it used to close the film (or start the next episode).
    @Test func aStreamThatStopsMidFilmPicksUpWhereItStopped() async {
        let engine = FakeVideoPlayerEngine(), store = Store()
        let model = makeModel(engine: engine, store: store)
        model.start(); await model.waitForIdleForTesting()
        await playTo(2401, duration: 7200, model, engine)
        engine.emit(.state(.ended)); await model.waitForIdleForTesting()
        #expect(!model.shouldDismiss)
        #expect(engine.loadCount == 2)                   // reopened…
        #expect((engine.seeks.last ?? 0) >= 2400)        // …where it stopped
    }

    /// …but a file that really does stop there (a short encode, a container that overstates its
    /// length) must still end, not loop on reopening.
    @Test func aSecondStopAtTheSamePlaceIsTheRealEnd() async {
        let engine = FakeVideoPlayerEngine(), store = Store()
        let model = makeModel(engine: engine, store: store)
        model.start(); await model.waitForIdleForTesting()
        await playTo(2401, duration: 7200, model, engine)
        engine.emit(.state(.ended)); await model.waitForIdleForTesting()
        await playTo(2405, duration: 7200, model, engine)
        engine.emit(.state(.ended)); await model.waitForIdleForTesting()
        #expect(model.shouldDismiss)
        #expect(engine.loadCount == 2)
    }

    /// Near the real end it is simply the end.
    @Test func anEndInTheLastMinuteIsTheEnd() async {
        let engine = FakeVideoPlayerEngine(), store = Store()
        let model = makeModel(engine: engine, store: store)
        model.start(); await model.waitForIdleForTesting()
        await playTo(7170, duration: 7200, model, engine)
        engine.emit(.state(.ended)); await model.waitForIdleForTesting()
        #expect(model.shouldDismiss)
        #expect(engine.loadCount == 1)
    }

    // MARK: - A picture that stops

    /// libvlc says nothing while its input is starved — no `.buffering` until the data comes back —
    /// so a stream that stalled mid-film froze the picture with no feedback at all: no spinner, a
    /// bar that stopped, and the viewer left to wonder whether the app had died.
    @Test func aFrozenPictureShowsLoadingEvenWhenTheEngineSaysNothing() async {
        let engine = FakeVideoPlayerEngine(), store = Store()
        let model = PlayerModel(request: Fixture.request(), engine: engine,
                                unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { key, _, position, _, _ in
                                    await MainActor.run { store.record(key, position) }
                                },
                                subtitles: nil, stallThreshold: 0.05)
        model.start(); await model.waitForIdleForTesting()
        await playTo(100, duration: 6000, model, engine)
        #expect(model.isBuffering == false)
        for _ in 0..<200 where !model.isBuffering { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(model.isBuffering == true)                 // no tick for longer than the threshold
        engine.emit(.time(.init(position: 101, duration: 6000))); await model.waitForIdleForTesting()
        #expect(model.isBuffering == false)                // moving again
    }

    /// …but a paused film is not stalled.
    @Test func aPausedFilmIsNotStalled() async {
        let engine = FakeVideoPlayerEngine(), store = Store()
        let model = PlayerModel(request: Fixture.request(), engine: engine,
                                unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, _, _, _ in }, subtitles: nil,
                                stallThreshold: 0.05)
        model.start(); await model.waitForIdleForTesting()
        await playTo(100, duration: 6000, model, engine)
        engine.emit(.state(.paused)); await model.waitForIdleForTesting()
        try? await Task.sleep(for: .milliseconds(300))
        #expect(model.isBuffering == false)
        _ = store
    }

    // MARK: - Leaving the app

    /// The TV button mid-film: nothing paused or recorded, libvlc kept playing into a suspended
    /// app, and the viewer came back to a film that had run on without them.
    @Test func leavingTheAppPausesAndRecordsThePlace() async {
        let engine = FakeVideoPlayerEngine(), store = Store()
        let model = makeModel(engine: engine, store: store)
        model.start(); await model.waitForIdleForTesting()
        await playTo(1234, duration: 6000, model, engine)
        await model.appDidLeaveForeground()
        #expect(engine.pauseCount == 1)
        #expect(store.saved["m1"] == 1234)
    }
}
