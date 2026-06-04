import Testing
import Foundation
@testable import Seret
import DebridCore

@MainActor
@Suite struct PlayerModelTests {
    private func makeModel(
        request: PlaybackRequest,
        engine: FakeVideoPlayerEngine,
        unrestrict: @escaping (String) async throws -> URL = { _ in URL(string: "https://cdn/x.mkv")! },
        subtitles: SubtitleProvider? = nil,
        recorded: @escaping (Double, Double) async -> Void = { _, _ in }
    ) -> PlayerModel {
        PlayerModel(request: request, engine: engine, unrestrict: unrestrict,
                    recordProgress: recorded, subtitles: subtitles)
    }

    @Test func startUnrestrictsLoadsAndPlays() async {
        let engine = FakeVideoPlayerEngine()
        var unrestrictedLink: String?
        let model = makeModel(request: Fixture.request(), engine: engine,
                              unrestrict: { link in unrestrictedLink = link; return URL(string: "https://cdn/x.mkv")! })
        model.start()
        await model.waitForIdleForTesting()
        #expect(unrestrictedLink == "rd://link")
        #expect(engine.loadedURL == URL(string: "https://cdn/x.mkv"))
        #expect(engine.playCalled == true)
        #expect(engine.seekedTo == nil)
    }

    @Test func seeksToResumePositionWhenProvided() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(resumeAt: 615), engine: engine)
        model.start()
        await model.waitForIdleForTesting()
        #expect(engine.seekedTo == 615)
    }

    @Test func mapsEngineStatesToPhase() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine)
        model.start()
        await model.waitForIdleForTesting()
        engine.emit(.state(.buffering)); await model.waitForIdleForTesting()
        #expect(model.phase == .buffering)
        engine.emit(.state(.playing));   await model.waitForIdleForTesting()
        #expect(model.phase == .playing)
        engine.emit(.state(.paused));    await model.waitForIdleForTesting()
        #expect(model.phase == .paused)
    }

    @Test func unrestrictFailureSurfacesFailedPhase() async {
        struct Boom: Error {}
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine, unrestrict: { _ in throw Boom() })
        model.start()
        await model.waitForIdleForTesting()
        guard case .failed = model.phase else { Issue.record("expected .failed, got \(model.phase)"); return }
    }

    @Test func savesAtMostEveryFiveSeconds() async {
        let engine = FakeVideoPlayerEngine()
        var saves: [(Double, Double)] = []
        let model = makeModel(request: Fixture.request(), engine: engine, recorded: { p, d in saves.append((p, d)) })
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 1, duration: 100))); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 3, duration: 100))); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 6, duration: 100))); await model.waitForIdleForTesting()
        #expect(saves.map(\.0) == [1, 6])
    }

    @Test func endedSavesFinalAndRequestsDismiss() async {
        let engine = FakeVideoPlayerEngine()
        var saves: [(Double, Double)] = []
        let model = makeModel(request: Fixture.request(), engine: engine, recorded: { p, d in saves.append((p, d)) })
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 95, duration: 100))); await model.waitForIdleForTesting()
        engine.emit(.state(.ended)); await model.waitForIdleForTesting()
        #expect(model.phase == .ended)
        #expect(model.shouldDismiss == true)
        #expect(saves.last?.0 == 95)
    }

    @Test func doubleEndedSavesAndDismissesOnce() async {
        let engine = FakeVideoPlayerEngine()
        var saves: [(Double, Double)] = []
        let model = makeModel(request: Fixture.request(), engine: engine,
                              recorded: { p, d in saves.append((p, d)) })
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.ended)); await model.waitForIdleForTesting()
        engine.emit(.state(.ended)); await model.waitForIdleForTesting()
        #expect(saves.count == 1)              // finish() guarded against the second .ended
        #expect(model.shouldDismiss == true)
    }

    @Test func teardownPersistsCurrentPosition() async {
        let engine = FakeVideoPlayerEngine()
        var saves: [(Double, Double)] = []
        let model = makeModel(request: Fixture.request(), engine: engine, recorded: { p, d in saves.append((p, d)) })
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 42, duration: 100))); await model.waitForIdleForTesting()
        await model.teardown()
        #expect(saves.last?.0 == 42)
    }
}
