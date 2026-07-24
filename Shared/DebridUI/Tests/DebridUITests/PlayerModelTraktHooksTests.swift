import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// The additive Trakt hooks on PlayerModel: fractional resume (Trakt stores a percentage, not
/// seconds) and the scrobble lifecycle. All hooks default to nil, so the pre-Trakt behavior — and
/// every existing PlayerModelTests expectation — is unchanged when they aren't wired.
@MainActor
@Suite struct PlayerModelTraktHooksTests {
    final class Box: @unchecked Sendable {
        var starts: [Double] = []
        var pauses: [Double] = []
        var stops: [Double] = []
    }

    private func makeModel(
        request: PlaybackRequest,
        engine: FakeVideoPlayerEngine,
        resolveResumeFraction: ((String) async -> Double?)? = nil,
        box: Box? = nil
    ) -> PlayerModel {
        PlayerModel(request: request, engine: engine,
                    unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _ in }, subtitles: nil,
                    resolveResumeFraction: resolveResumeFraction,
                    onScrobbleStart: box.map { b in { f in b.starts.append(f) } },
                    onScrobblePause: box.map { b in { f in b.pauses.append(f) } },
                    onScrobbleStop: box.map { b in { f in b.stops.append(f) } })
    }

    @Test func fractionalResumeSeeksOnceDurationIsKnown() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine,
                              resolveResumeFraction: { _ in 0.5 })
        model.start(); await model.waitForIdleForTesting()
        // At load the duration is unknown, so no seconds are computable → no early seek.
        #expect(engine.seeks == [])
        // First tick reports a 1000s runtime → 50% becomes a 500s target and the deferred seek fires.
        engine.emit(.time(.init(position: 0.2, duration: 1000))); await model.waitForIdleForTesting()
        #expect(engine.seeks == [500])
        // Arriving at the point completes the resume (no redundant second seek).
        engine.emit(.time(.init(position: 500.2, duration: 1000))); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 500.9, duration: 1000))); await model.waitForIdleForTesting()
        #expect(engine.seeks == [500])
        #expect(model.phase == .playing)
    }

    @Test func fromStartIgnoresFractionalResume() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(fromStart: true), engine: engine,
                              resolveResumeFraction: { _ in 0.5 })
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 0.2, duration: 1000))); await model.waitForIdleForTesting()
        #expect(engine.seeks == [])          // Start over must never resume
    }

    @Test func fullyWatchedFractionDoesNotSeek() async {
        // Trakt drops an item from /sync/playback past ~80%, but guard the degenerate 1.0 anyway —
        // seeking to EOF lands at the end (instant "ended" / stuck buffer).
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine,
                              resolveResumeFraction: { _ in 1.0 })
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 0.2, duration: 1000))); await model.waitForIdleForTesting()
        #expect(engine.seeks == [])
    }

    @Test func scrobbleStartAndPauseFireOnStateChanges() async {
        let engine = FakeVideoPlayerEngine(); let box = Box()
        let model = makeModel(request: Fixture.request(), engine: engine, box: box)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 250, duration: 1000))); await model.waitForIdleForTesting()
        engine.emit(.state(.playing)); await model.waitForIdleForTesting()
        #expect(box.starts == [0.25])
        engine.emit(.state(.paused)); await model.waitForIdleForTesting()
        #expect(box.pauses == [0.25])
    }

    @Test func scrobbleStopFiresOnTeardownWithFinalFraction() async {
        let engine = FakeVideoPlayerEngine(); let box = Box()
        let model = makeModel(request: Fixture.request(), engine: engine, box: box)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 900, duration: 1000))); await model.waitForIdleForTesting()
        await model.teardown()
        #expect(box.stops == [0.9])
    }
}
