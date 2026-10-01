import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// Player regressions found by reviewing fix/polish-sweep-2026-10-01 against itself. The resume
/// rule here is the REAL one — the store row's `resumePosition`, exactly what AppSession wires —
/// because the existing fakes return raw positions and so could not see the first of these.
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
                            store.writes.append((position, finished))
                            store.rows[key] = WatchState(contentKey: key, sourceKey: source,
                                                         positionSeconds: position,
                                                         durationSeconds: duration,
                                                         finished: finished, updatedAt: .now)
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
