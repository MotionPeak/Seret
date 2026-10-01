import Testing
import Foundation
import SwiftData
@testable import DebridUI
import DebridCore

/// Parks every progress write made while armed until `open()` — so a test can act while a write is
/// in flight.
@MainActor
private final class ProgressGate {
    private var armed = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var hasWaiter: Bool { !waiters.isEmpty }
    func arm() { armed = true }
    func open() {
        armed = false
        let held = waiters
        waiters = []
        held.forEach { $0.resume() }
    }
    func pass() async {
        guard armed else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

/// Player regressions found by reviewing fix/polish-sweep-2026-10-01 against itself. The resume
/// rule here is the REAL one — the store row's `resumePosition`, exactly what AppSession wires —
/// because the existing fakes return raw positions and so could not see the first of these. And
/// the row is written the way `LocalWatchProvider.record` writes it: the player's `finished` ORed
/// with the store's own subtitle-blind finish line (the fake once passed `finished` straight
/// through, which hid a late-cue drop restarting from 0:00 — see `PlayerStoreBackedTests`).
@MainActor
@Suite struct PlayerReviewRegressionTests {

    @MainActor final class Store {
        var rows: [String: WatchState] = [:]
        var writes: [(position: Double, finished: Bool)] = []
    }

    private func makeModel(store: Store, engine: FakeVideoPlayerEngine,
                           request: PlaybackRequest = Fixture.request(),
                           stallThreshold: Double = 2.5) -> PlayerModel {
        PlayerModel(request: request, engine: engine,
                    unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { key, source, position, duration, finished in
                        await MainActor.run {
                            let stored = finished || WatchThreshold.hasReachedEnd(
                                position: position, duration: duration, lastSubtitleCue: nil)
                            store.writes.append((position, stored))
                            store.rows[key] = WatchState(contentKey: key, sourceKey: source,
                                                         positionSeconds: position,
                                                         durationSeconds: duration,
                                                         finished: stored, updatedAt: .now)
                        }
                    },
                    subtitles: nil,
                    resolveResume: { key in await MainActor.run { store.rows[key]?.resumePosition } },
                    stallThreshold: stallThreshold)
    }

    /// libvlc reporting the end of the file early INSIDE the credits — a dropped connection, a
    /// container that overstates its length. The early-EOF recovery reopened the film there, but a
    /// finished title has no resume point, so it restarted from 0:00 and its first tick un-finished
    /// it. Past the finish line, an end is the end.
    @Test func anEarlyEndInTheCreditsIsTheEnd() async {
        let engine = FakeVideoPlayerEngine(), store = Store()
        let model = makeModel(store: store, engine: engine)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: 6799, duration: 7200)))
        engine.emit(.time(.init(position: 6800, duration: 7200)))
        await model.waitForIdleForTesting()

        engine.emit(.state(.ended)); await model.waitForIdleForTesting()

        #expect(engine.loadCount == 1, "no reopen")
        #expect(model.shouldDismiss)
        #expect(store.writes.last?.finished == true)
    }

    /// …while a drop well BEFORE the finish line still picks up where it stopped.
    @Test func anEarlyEndMidFilmStillReopensAtThePlace() async {
        let engine = FakeVideoPlayerEngine(), store = Store()
        let model = makeModel(store: store, engine: engine)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: 2399, duration: 7200)))
        engine.emit(.time(.init(position: 2400, duration: 7200)))
        await model.waitForIdleForTesting()

        engine.emit(.state(.ended)); await model.waitForIdleForTesting()

        #expect(engine.loadCount == 2, "reopened")
        #expect(model.shouldDismiss == false)
        #expect(model.position == 2400)
    }

    /// …and so does a drop past a finish line drawn EARLY. A subtitle whose last line ends at 82% of
    /// a 100-minute film puts the line there; a drop at 83% leaves 16:40 — more than any credits
    /// run — and the store keeps that place. The film was closed on the viewer anyway, because the
    /// recovery asked "past the finish line?" instead of "is there a place to come back to?".
    @Test func aDropAfterAnEarlyFinishLineStillReopensAtThePlace() async {
        let engine = FakeVideoPlayerEngine(), store = Store()
        let model = makeModel(store: store, engine: engine)
        model.start(); await model.waitForIdleForTesting()
        model.contentEndTime = 4900                     // the subtitle's last line
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: 4999, duration: 6000)))
        engine.emit(.time(.init(position: 5000, duration: 6000)))
        await model.waitForIdleForTesting()

        engine.emit(.state(.ended)); await model.waitForIdleForTesting()

        #expect(store.rows[Fixture.request().contentKey]?.resumePosition == 5000)
        #expect(engine.loadCount == 2, "reopened")
        #expect(model.shouldDismiss == false)
    }

    /// A swap whose link fails: the Retry screen must be the only thing on it. The swap's reload
    /// raised the buffering hint and the failure set the phase and left the hint up — and the
    /// iPhone's spinner, shown for every wait that is not a cold open, spun over Retry.
    @Test func aFailureLowersTheBufferingHint() async {
        let engine = FakeVideoPlayerEngine()
        let model = PlayerModel(request: Fixture.showRequest(playingEpisode: 1), engine: engine,
                                unrestrict: { link in
                                    if link.contains("e2") { throw URLError(.badServerResponse) }
                                    return URL(string: "https://cdn/x.mkv")!
                                },
                                recordProgress: { _, _, _, _, _ in }, subtitles: nil)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: 600, duration: 1320)))
        engine.emit(.time(.init(position: 601, duration: 1320)))
        await model.waitForIdleForTesting()

        model.playNext(); await model.waitForIdleForTesting()

        #expect(model.phase.isFailed)
        #expect(model.isBuffering == false)
    }

    /// An episode picked from the strip WHILE a dropped stream's progress was being written: the
    /// recovery then carried on — set the OLD episode's playhead as the place to reopen at and
    /// reloaded — so the picked episode opened at 40:00 instead of its own 5:00.
    @Test func aSwapDuringTheDropWriteKeepsTheNewEpisodesOwnPlace() async {
        let gate = ProgressGate()
        let engine = FakeVideoPlayerEngine()
        let request = Fixture.showRequest(episodes: 3, playingEpisode: 1)
        let model = PlayerModel(
            request: request, engine: engine,
            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
            recordProgress: { _, _, _, _, _ in await gate.pass() },
            subtitles: nil,
            resolveResume: { key in key.hasSuffix(":s1e2") ? 300 : nil })   // E2 saved at 5:00
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: 2399, duration: 3000)))
        engine.emit(.time(.init(position: 2400, duration: 3000)))
        await model.waitForIdleForTesting()

        gate.arm()
        engine.emit(.state(.ended))                                  // the drop, at 40:00 of 50:00
        for _ in 0..<400 where !gate.hasWaiter { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(gate.hasWaiter, "the recovery never reached its progress write")
        model.play(request.item.seasons[0].episodes[1])              // E2, picked meanwhile
        gate.open()
        await model.waitForIdleForTesting()

        #expect(model.contentKey.hasSuffix(":s1e2"))
        #expect(model.position == 300, "E2 opened at \(model.position)")
        #expect(engine.seeks.last == 300, "engine seeks: \(engine.seeks)")
        await model.teardown()
    }

    /// …and a skip ON the failure screen — Control Center and AirPods route straight to `skip` —
    /// raised the hint again, with nothing left to lower it.
    @Test func aSkipOnTheFailureScreenDoesNotRaiseTheHint() async {
        let engine = FakeVideoPlayerEngine()
        let model = PlayerModel(request: Fixture.request(), engine: engine,
                                unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                                recordProgress: { _, _, _, _, _ in }, subtitles: nil)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: 600, duration: 6000)))
        engine.emit(.time(.init(position: 601, duration: 6000)))
        await model.waitForIdleForTesting()
        engine.emit(.state(.failed("libvlc error"))); await model.waitForIdleForTesting()
        #expect(model.phase.isFailed && !model.isBuffering)

        model.skip(10)
        #expect(model.isBuffering == false)
        model.scrub(to: 900)
        #expect(model.isBuffering == false)
        await model.teardown()
    }

    /// "From Start" on a title saved at 1:00:00, then a failure between libvlc's `.playing` and the
    /// first tick: the intent was dropped at `.playing` (the first-frame mark), so Retry resumed
    /// at 1:00:00. It now holds until the playhead is real.
    @Test func fromStartSurvivesAFailureBeforeTheFirstTick() async {
        let engine = FakeVideoPlayerEngine(), store = Store()
        store.rows["m1"] = WatchState(contentKey: "m1", sourceKey: "t1#-", positionSeconds: 3600,
                                      durationSeconds: 7200, finished: false, updatedAt: .now)
        let model = makeModel(store: store, engine: engine, request: Fixture.request(fromStart: true))
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.playing)); await model.waitForIdleForTesting()
        engine.emit(.state(.failed("boom"))); await model.waitForIdleForTesting()

        model.retry(); await model.waitForIdleForTesting()

        #expect(!engine.seeks.contains(3600), "seeks: \(engine.seeks)")
    }

    /// Resuming after a pause longer than the stall threshold read as a stall at once: the clock
    /// still held the last advance from before the pause, so "Buffering…" flashed over a film that
    /// was playing. Within one threshold of pressing play, nothing is a stall.
    @Test func resumingFromAPauseIsNotAStall() async {
        let engine = FakeVideoPlayerEngine(), store = Store()
        let model = makeModel(store: store, engine: engine, stallThreshold: 0.3)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: 99, duration: 6000)))
        engine.emit(.time(.init(position: 100, duration: 6000)))
        await model.waitForIdleForTesting()
        engine.emit(.state(.paused)); await model.waitForIdleForTesting()
        try? await Task.sleep(for: .milliseconds(600))          // a pause longer than the threshold

        engine.emit(.state(.playing)); await model.waitForIdleForTesting()

        var raised = false
        for _ in 0..<20 where !raised {                         // ~200ms: inside one threshold
            try? await Task.sleep(for: .milliseconds(10))
            raised = model.isBuffering
        }
        #expect(!raised)
    }
}

extension SwiftDataSuite {
    /// The same player over the REAL local watch store, wired exactly as `AppSession.makePlayer`
    /// wires it — the store's own rules are the point.
    @MainActor @Suite struct PlayerStoreBackedTests {
        private func makeModel(_ p: LocalWatchProvider, engine: FakeVideoPlayerEngine) -> PlayerModel {
            PlayerModel(request: Fixture.request(), engine: engine,
                        unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                        recordProgress: { key, source, position, duration, finished in
                            guard duration > 0 else { return }
                            try? await p.record(contentKey: key, sourceKey: source, positionSeconds: position,
                                                durationSeconds: duration, finished: finished, profileID: "p1")
                        },
                        subtitles: nil,
                        resolveResume: { key in
                            (try? await p.progress(forContentKey: key, profileID: "p1"))?.resumePosition
                        })
        }

        private func provider() throws -> LocalWatchProvider {
            let c = try ModelContainer(for: WatchProgress.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return LocalWatchProvider(store: LocalWatchStore(modelContainer: c), profileID: { "p1" })
        }

        /// A subtitle whose last line runs to 98% of a 100-minute film, and a drop at 93%: mid-
        /// dialogue to the player, so it reopens — but the store had already filed the title
        /// finished at its own 92% line, with no resume point inside the "credits". Asked where to
        /// reopen, it said nowhere: the film restarted from 0:00, and its first tick un-finished it.
        @Test func aDropBeforeALateLastCueReopensAtThePlace() async throws {
            let p = try provider()
            let engine = FakeVideoPlayerEngine()
            let model = makeModel(p, engine: engine)
            model.start(); await model.waitForIdleForTesting()
            model.contentEndTime = 5900
            engine.emit(.state(.playing))
            engine.emit(.time(.init(position: 5599, duration: 6000)))
            engine.emit(.time(.init(position: 5600, duration: 6000)))
            await model.waitForIdleForTesting()

            engine.emit(.state(.ended)); await model.waitForIdleForTesting()     // the drop

            #expect(engine.loadCount == 2, "reopened")
            #expect(model.position == 5600, "the reopen aimed at \(model.position)")

            engine.emit(.state(.playing))                                        // reopened, at the place
            engine.emit(.time(.init(position: 5600, duration: 6000)))
            engine.emit(.time(.init(position: 5601, duration: 6000)))
            await model.waitForIdleForTesting()
            let row = try await p.progress(forContentKey: "m1", profileID: "p1")
            #expect(row?.finished == true, "the title lost its finish")
            #expect((row?.positionSeconds ?? 0) >= 5600, "the place: \(String(describing: row?.positionSeconds))")
            #expect(model.reopenAt == nil)
            await model.teardown()
        }

        /// …and a Retry after the reopen itself failed still comes back to the place, rather than
        /// asking the store (which still says nowhere).
        @Test func aRetryAfterAFailedReopenStillComesBackToThePlace() async throws {
            let p = try provider()
            let engine = FakeVideoPlayerEngine()
            let model = makeModel(p, engine: engine)
            model.start(); await model.waitForIdleForTesting()
            model.contentEndTime = 5900
            engine.emit(.state(.playing))
            engine.emit(.time(.init(position: 5599, duration: 6000)))
            engine.emit(.time(.init(position: 5600, duration: 6000)))
            await model.waitForIdleForTesting()
            engine.emit(.state(.ended)); await model.waitForIdleForTesting()

            engine.emit(.state(.failed("the reopen failed"))); await model.waitForIdleForTesting()
            #expect(model.phase.isFailed)
            model.retry(); await model.waitForIdleForTesting()

            #expect(engine.loadCount == 3)
            #expect(model.position == 5600, "the retry aimed at \(model.position)")
            await model.teardown()
        }
    }
}
