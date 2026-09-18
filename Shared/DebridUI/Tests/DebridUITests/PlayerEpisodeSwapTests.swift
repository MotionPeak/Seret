import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// The in-place episode swap leaves a window open: `switchTo()` resets the model to the NEW
/// episode synchronously, but the engine keeps playing the OLD file until `loadCurrentSource()`
/// has awaited the resume lookup and the RD unrestrict — seconds on a cold link.
///
/// Every `.time` event VLCKit emits inside that window belongs to the OUTGOING file, and `tick()`
/// had no way to tell. It attributed the old file's near-end playhead to the new episode, which is
/// the single defect behind three separate viewer reports (see each test).
@MainActor
@Suite struct PlayerEpisodeSwapTests {

    /// Captures what the model asked to persist, keyed by content — enough to prove WHICH episode
    /// a write landed on, not merely that one happened.
    @MainActor final class Writes {
        private(set) var entries: [(key: String, position: Double, duration: Double)] = []
        func record(_ key: String, _ position: Double, _ duration: Double) {
            entries.append((key, position, duration))
        }
        func positions(forKey key: String) -> [Double] {
            entries.filter { $0.key == key }.map(\.position)
        }
    }

    /// A model whose unrestrict blocks until released, so the swap window can be held open for the
    /// length of the test — exactly as a slow RD link holds it open on the device.
    private func makeModel(engine: FakeVideoPlayerEngine, writes: Writes,
                           gate: Gate) -> PlayerModel {
        PlayerModel(request: Fixture.showRequest(episodes: 3, playingEpisode: 1),
                    engine: engine,
                    unrestrict: { _ in
                        await gate.waitIfClosed()
                        return URL(string: "https://cdn/x.mkv")!
                    },
                    recordProgress: { key, _, position, duration in
                        await MainActor.run { writes.record(key, position, duration) }
                    },
                    subtitles: nil)
    }

    /// Opens once and stays open; the first load must not block, only the swap's.
    ///
    /// Every settle inside a closed gate is `waitForIdleWhileLoadIsHeldForTesting()`: the swap's
    /// load is blocked HERE, on purpose, so a settle that waited for it would wait for this test to
    /// reach `gate.open()` — which is below the settle.
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

    private func warmUp(_ model: PlayerModel, _ engine: FakeVideoPlayerEngine,
                        to position: Double, duration: Double) async {
        model.start()
        await model.waitForIdleForTesting()
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: position, duration: duration)))
        engine.emit(.time(.init(position: position + 0.5, duration: duration)))
        await model.waitForIdleForTesting()
    }

    // MARK: -

    /// **"Playing episode one it loads episode 3."**
    ///
    /// After the swap to E2 the old file's ticks still arrived, carrying a playhead ~99% through
    /// E1's runtime. `tick()` promoted the phase to `.playing` off that advance and handed the
    /// position to `maybeShowUpNext()`, which compared it against a threshold computed from the
    /// same stale duration — so the Up Next bar re-armed immediately, counted down over E2's load,
    /// and advanced again. The viewer picked E1 and landed on E3.
    @Test func staleTicksFromTheOutgoingEpisodeDoNotReArmUpNext() async {
        let engine = FakeVideoPlayerEngine()
        let writes = Writes()
        let gate = Gate()
        let model = makeModel(engine: engine, writes: writes, gate: gate)
        await warmUp(model, engine, to: 175, duration: 200)

        await gate.close()          // hold E2's unrestrict open — the swap window stays wide
        model.playNext()            // → E2, but the engine is still on E1
        await model.waitForIdleWhileLoadIsHeldForTesting()

        // E1 keeps ticking near its end while E2 is still being resolved.
        for t in [176.0, 177.0, 178.0] {
            engine.emit(.time(.init(position: t, duration: 200)))
        }
        await model.waitForIdleWhileLoadIsHeldForTesting()

        // The bar re-arming here is the whole defect: its countdown then advances again, unattended.
        #expect(model.upNextVisible == false)
        #expect(model.currentEpisode?.number == 2)
        await gate.open()
    }

    /// **"Resuming doesn't keep the resume option."**
    ///
    /// The same stale ticks were written to the store under the NEW episode's content key. E2 was
    /// therefore recorded at ~99% of E1's runtime before a single frame of it had played: past the
    /// 80% mark, so it counted as finished, its resume point was discarded, and its title page
    /// offered "Play" instead of "Resume".
    @Test func staleTicksAreNotRecordedAgainstTheIncomingEpisode() async {
        let engine = FakeVideoPlayerEngine()
        let writes = Writes()
        let gate = Gate()
        let model = makeModel(engine: engine, writes: writes, gate: gate)
        await warmUp(model, engine, to: 175, duration: 200)

        await gate.close()
        let episodeOneKey = model.contentKey
        model.playNext()
        await model.waitForIdleWhileLoadIsHeldForTesting()
        let episodeTwoKey = model.contentKey

        for t in [176.0, 177.0, 178.0] {
            engine.emit(.time(.init(position: t, duration: 200)))
        }
        await model.waitForIdleWhileLoadIsHeldForTesting()

        #expect(writes.positions(forKey: episodeTwoKey).isEmpty)
        // …and the episode the viewer actually finished is finalised at its tail, not lost.
        #expect(writes.positions(forKey: episodeOneKey).last == 175.5)
        await gate.open()
    }

    /// **"Skipping loads for too long" / the spinner that never clears.**
    ///
    /// `markRendered()` disarms the load watchdog, and a stale tick reached it — so the timeout
    /// protecting the INCOMING episode's load was cancelled by the OUTGOING one's playhead. A dead
    /// link then sat on the loading overlay forever with no error and no Retry.
    @Test func staleTicksDoNotDisarmTheIncomingLoadWatchdog() async {
        let engine = FakeVideoPlayerEngine()
        let writes = Writes()
        let gate = Gate()
        let model = makeModel(engine: engine, writes: writes, gate: gate)
        await warmUp(model, engine, to: 175, duration: 200)

        await gate.close()
        model.playNext()
        await model.waitForIdleWhileLoadIsHeldForTesting()

        for t in [176.0, 177.0, 178.0] {
            engine.emit(.time(.init(position: t, duration: 200)))
        }
        await model.waitForIdleWhileLoadIsHeldForTesting()

        // Still waiting on E2's first frame — the overlay must still be a cold load.
        #expect(model.hasRenderedFrame == false)
        await gate.open()
    }

    /// **The same window, but the stale event is a STATE change rather than a tick.**
    ///
    /// `tick()` and `.paused` are both gated against the outgoing media; `.playing` was not. Any
    /// rebuffer of the still-playing outgoing file emits `.buffering` → `.playing`, and the
    /// unguarded `.playing` called `markRendered()`, which clears `isSwitching`. That guard is the
    /// only thing swallowing the `.ended` the engine emits when `load()` replaces the media — so
    /// the swap's own teardown was read as "E2 finished" and auto-advanced again, to E3.
    @Test func aStalePlayingStateFromTheOutgoingEpisodeDoesNotClearTheSwapGuard() async {
        let engine = FakeVideoPlayerEngine()
        let writes = Writes()
        let gate = Gate()
        let model = makeModel(engine: engine, writes: writes, gate: gate)
        await warmUp(model, engine, to: 100, duration: 200)

        await gate.close()          // hold E2's unrestrict open
        model.playNext()            // → E2, engine still holds E1
        await model.waitForIdleWhileLoadIsHeldForTesting()
        #expect(model.currentEpisode?.number == 2)

        // E1 rebuffers and recovers while E2 is still resolving.
        engine.emit(.state(.buffering))
        engine.emit(.state(.playing))
        await model.waitForIdleWhileLoadIsHeldForTesting()

        // …then `engine.load()` replaces the media, which VLCKit reports as stopped → `.ended`.
        engine.emit(.state(.ended))
        await model.waitForIdleWhileLoadIsHeldForTesting()

        // Still E2. Without the guard this is E3.
        #expect(model.currentEpisode?.number == 2)
        await gate.open()
    }

    /// The same unguarded `.playing` also set `hasRenderedFrame`, which is what the load watchdog
    /// checks before surfacing a dead link. A stale `.playing` therefore disarmed the watchdog for
    /// the INCOMING episode: a link that never opened left the spinner up for good, with no Retry.
    @Test func aStalePlayingStateDoesNotMarkTheIncomingEpisodeAsRendered() async {
        let engine = FakeVideoPlayerEngine()
        let writes = Writes()
        let gate = Gate()
        let model = makeModel(engine: engine, writes: writes, gate: gate)
        await warmUp(model, engine, to: 100, duration: 200)

        await gate.close()
        model.playNext()
        await model.waitForIdleWhileLoadIsHeldForTesting()

        engine.emit(.state(.playing))
        await model.waitForIdleWhileLoadIsHeldForTesting()

        #expect(model.hasRenderedFrame == false)
        #expect(model.isSwitching == true)
        await gate.open()
    }
}
