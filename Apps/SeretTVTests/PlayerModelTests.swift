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
        recorded: @escaping (Double, Double) async -> Void = { _, _ in },
        autoHideDelay: Double = 4
    ) -> PlayerModel {
        PlayerModel(request: request, engine: engine, unrestrict: unrestrict,
                    recordProgress: recorded, subtitles: subtitles, autoHideDelay: autoHideDelay)
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

    @Test func controlsAutoHideWhilePlayingThenWakeShows() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine, autoHideDelay: 0.02)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.playing)); await model.waitForIdleForTesting()
        #expect(model.controlsVisible == true)              // visible as playback starts
        try? await Task.sleep(nanoseconds: 60_000_000)      // past autoHideDelay
        #expect(model.controlsVisible == false)             // auto-hid
        model.showControls()
        #expect(model.controlsVisible == true)              // woke back up
    }

    @Test func scrubModeNeverAutoHidesControls() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine, autoHideDelay: 0.02)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.playing)); await model.waitForIdleForTesting()
        model.beginScrub()
        try? await Task.sleep(nanoseconds: 60_000_000)      // past autoHideDelay
        #expect(model.isScrubbing == true)
        #expect(model.controlsVisible == true)              // stays up mid-scrub
    }

    @Test func pausedKeepsControlsVisible() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine, autoHideDelay: 0.02)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.paused)); await model.waitForIdleForTesting()
        try? await Task.sleep(nanoseconds: 60_000_000)
        #expect(model.controlsVisible == true)              // a paused viewer keeps the controls
    }

    @Test func scrubPreviewTracksThenCommitsSeek() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 50, duration: 100))); await model.waitForIdleForTesting()
        model.beginScrub()
        #expect(model.isScrubbing == true)
        #expect(model.scrubTarget == 50)                 // starts at the playhead
        model.updateScrub(by: 20)
        #expect(model.scrubTarget == 70)
        model.updateScrub(by: 1_000)                     // clamps to duration
        #expect(model.scrubTarget == 100)
        model.updateScrub(by: -10_000)                   // clamps to 0
        #expect(model.scrubTarget == 0)
        model.commitScrub()
        #expect(engine.seekedTo == 0)
        #expect(model.isScrubbing == false)
    }

    @Test func cancelScrubLeavesPlayheadAndDoesNotSeek() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine)   // no resumeAt → no startup seek
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 50, duration: 100))); await model.waitForIdleForTesting()
        model.beginScrub(); model.updateScrub(by: 20)
        model.cancelScrub()
        #expect(model.isScrubbing == false)
        #expect(engine.seekedTo == nil)                  // never sought
    }

    @Test func tracksChangedRefreshesTrackLists() async {
        // VLCKit discovers elementary streams asynchronously (and an on-demand external subtitle
        // appears after playback starts). A `.tracksChanged` event must re-pull the engine's lists
        // so the Subtitles & Audio panel reflects what's actually available.
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        #expect(model.audioTracks.isEmpty)
        engine.audioTracks = [MediaTrack(id: "audio/0", kind: .audio, name: "English", language: "en")]
        engine.subtitleTracks = [MediaTrack(id: "spu/1", kind: .subtitle, name: "Hebrew", language: "he")]
        engine.emit(.tracksChanged); await model.waitForIdleForTesting()
        #expect(model.audioTracks.map(\.id) == ["audio/0"])
        #expect(model.subtitleTracks.map(\.id) == ["spu/1"])
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
