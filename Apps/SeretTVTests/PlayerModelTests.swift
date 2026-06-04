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
        #expect(engine.stopCalled == true)
    }

    @Test func requestSubtitleDownloadsAttachesAndSelects() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 7, language: "he", release: nil, fileName: "he.srt", downloadCount: 1)]
        subs.downloadedURL = URL(fileURLWithPath: "/tmp/he.srt")
        let model = makeModel(request: Fixture.request(), engine: engine, subtitles: subs)
        model.start(); await model.waitForIdleForTesting()
        await model.requestSubtitle(language: "he")
        #expect(subs.searchedLanguages.last == ["he"])
        #expect(engine.addedSubtitles == [URL(fileURLWithPath: "/tmp/he.srt")])
        if case .attached = model.subtitleRows.first(where: { $0.language == "he" })?.state {} else {
            Issue.record("expected he row .attached, got \(String(describing: model.subtitleRows))")
        }
    }

    @Test func dailyCapMapsToCapReachedRow() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.downloadError = SubtitleError.dailyCapReached(resetTime: nil)
        subs.searchResults = [SubtitleResult(fileID: 7, language: "he", release: nil, fileName: nil, downloadCount: nil)]
        let model = makeModel(request: Fixture.request(), engine: engine, subtitles: subs)
        model.start(); await model.waitForIdleForTesting()
        await model.requestSubtitle(language: "he")
        #expect(model.subtitleRows.first(where: { $0.language == "he" })?.state == .capReached(nil))
    }

    @Test func noProviderLeavesRowsNoAccount() async {
        let model = makeModel(request: Fixture.request(), engine: FakeVideoPlayerEngine(), subtitles: nil)
        #expect(model.subtitleRows.allSatisfy { $0.state == .noAccount })
    }

    @Test func tryAnotherVersionAdvancesToNextSourceAndKeepsEventsFlowing() async {
        let s1 = Fixture.movieSource("rd://one")
        let s2 = Fixture.movieSource("rd://two")
        let engine = FakeVideoPlayerEngine()
        var unrestricted: [String] = []
        let model = makeModel(request: Fixture.request(sources: [s1, s2]), engine: engine,
                              unrestrict: { link in unrestricted.append(link); return URL(string: "https://cdn/x.mkv")! })
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.failed("boom"))); await model.waitForIdleForTesting()
        #expect(model.canTryAnotherVersion == true)
        model.tryAnotherVersion(); await model.waitForIdleForTesting()
        #expect(unrestricted == ["rd://one", "rd://two"])
        // The long-lived event loop must still deliver events for the newly-loaded source:
        engine.emit(.state(.playing)); await model.waitForIdleForTesting()
        #expect(model.phase == .playing)
    }

    @Test func retryReloadsCurrentSource() async {
        let engine = FakeVideoPlayerEngine()
        var unrestricted: [String] = []
        let model = makeModel(request: Fixture.request(), engine: engine,
                              unrestrict: { link in unrestricted.append(link); return URL(string: "https://cdn/x.mkv")! })
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.failed("boom"))); await model.waitForIdleForTesting()
        #expect(model.phase == .failed("boom"))
        model.retry(); await model.waitForIdleForTesting()
        #expect(unrestricted == ["rd://link", "rd://link"])   // same source reloaded
        #expect(model.phase != .failed("boom"))               // reload moved past the failure
    }

    @Test func canTryAnotherVersionFalseWhenSourcesExhausted() async {
        let s1 = Fixture.movieSource("rd://one")
        let s2 = Fixture.movieSource("rd://two")
        let model = makeModel(request: Fixture.request(sources: [s1, s2]), engine: FakeVideoPlayerEngine())
        model.start(); await model.waitForIdleForTesting()
        #expect(model.canTryAnotherVersion == true)
        model.tryAnotherVersion(); await model.waitForIdleForTesting()
        #expect(model.canTryAnotherVersion == false)
    }

    @Test func notAuthenticatedMapsToNoAccountRow() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 7, language: "he")]
        subs.downloadError = SubtitleError.notAuthenticated
        let model = makeModel(request: Fixture.request(), engine: engine, subtitles: subs)
        model.start(); await model.waitForIdleForTesting()
        await model.requestSubtitle(language: "he")
        #expect(model.subtitleRows.first(where: { $0.language == "he" })?.state == .noAccount)
    }

    @Test func playingInferredFromTimeProgressWithoutPlayingState() async {
        // VLCKit can stay in .buffering while actually rendering — the playhead moving must
        // clear the loading overlay even if no .playing state arrives.
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.buffering)); await model.waitForIdleForTesting()
        #expect(model.phase == .buffering)
        engine.emit(.time(.init(position: 3, duration: 100))); await model.waitForIdleForTesting()
        #expect(model.phase == .playing)        // promoted by time progress, no .playing state needed
    }

    @Test func lateBufferingDoesNotRevertPlaying() async {
        // VLCKit emits .buffering after playback starts; it must not flash the loading overlay back.
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.playing));   await model.waitForIdleForTesting()
        #expect(model.phase == .playing)
        engine.emit(.state(.buffering)); await model.waitForIdleForTesting()
        #expect(model.phase == .playing)        // stays playing — no flicker
    }
}
