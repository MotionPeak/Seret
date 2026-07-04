import Testing
import Foundation
@testable import DebridUI
import DebridCore

@MainActor
@Suite struct PlayerModelTests {
    private func makeModel(
        request: PlaybackRequest,
        engine: FakeVideoPlayerEngine,
        unrestrict: @escaping (String) async throws -> URL = { _ in URL(string: "https://cdn/x.mkv")! },
        subtitles: SubtitleProvider? = nil,
        trackPreferences: TrackPreferenceStoring? = nil,
        recorded: @escaping (String, String, Double, Double) async -> Void = { _, _, _, _ in },
        resolveResume: ((String) async -> Double?)? = nil,
        prefetchLink: ((String) -> Void)? = nil,
        autoHideDelay: Double = 4,
        seekCoalesceWindow: Double = 0.35
    ) -> PlayerModel {
        PlayerModel(request: request, engine: engine, unrestrict: unrestrict,
                    recordProgress: recorded, subtitles: subtitles,
                    trackPreferences: trackPreferences, resolveResume: resolveResume,
                    prefetchLink: prefetchLink, autoHideDelay: autoHideDelay,
                    seekCoalesceWindow: seekCoalesceWindow)
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
        #expect(engine.seekedTo == nil)           // no resume → no seek
    }

    @Test func resumeSeeksEarlyAtLoadAndFallsBackToDeferredSeekOnFirstTick() async {
        // Resume must NOT use a load-time start-time (that clips the timeline — no rewinding
        // before the point). Instead: a best-effort seek right after load (so when VLC honors it
        // there is no pre-roll at 0), the deferred seek as the fallback when ticks start near 0,
        // and the overlay held until the playhead actually arrives (no flash-0-then-jump).
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(resumeAt: 615), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        #expect(engine.seeks == [615])             // the early best-effort seek — via seek, never start-time
        engine.emit(.time(.init(position: 0.2, duration: 1000))); await model.waitForIdleForTesting()
        #expect(engine.seeks == [615, 615])        // ticks near 0 → VLC dropped it → deferred seek fired
        #expect(model.hasRenderedFrame == false)   // overlay still up — haven't reached the point
        engine.emit(.time(.init(position: 615.1, duration: 1000))); await model.waitForIdleForTesting()
        #expect(model.hasRenderedFrame == false)   // just arrived; wait for frames to advance
        engine.emit(.time(.init(position: 615.7, duration: 1000))); await model.waitForIdleForTesting()
        #expect(model.hasRenderedFrame == true)    // advancing past the point → overlay hides
        #expect(model.phase == .playing)
    }

    @Test func honoredEarlySeekCompletesResumeWithoutASecondSeek() async {
        // When VLC honors the load-time seek, the first ticks land AT the resume point — the
        // deferred fallback must not fire a redundant second seek (that would re-flush the buffer).
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(resumeAt: 615), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        #expect(engine.seeks == [615])
        engine.emit(.time(.init(position: 615.2, duration: 1000))); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 615.9, duration: 1000))); await model.waitForIdleForTesting()
        #expect(engine.seeks == [615])             // arrival detected — no second seek
        #expect(model.hasRenderedFrame == true)
        #expect(model.phase == .playing)
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

    @Test func savesAboutEverySecond() async {
        // Progress is persisted ~every 1s so cross-device resume stays fresh; sub-second ticks in
        // between are throttled out.
        let engine = FakeVideoPlayerEngine()
        var saves: [(Double, Double)] = []
        let model = makeModel(request: Fixture.request(), engine: engine, recorded: { _, _, p, d in saves.append((p, d)) })
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 1, duration: 100))); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 1.4, duration: 100))); await model.waitForIdleForTesting()   // <1s since last save → skipped
        engine.emit(.time(.init(position: 2.2, duration: 100))); await model.waitForIdleForTesting()   // ≥1s → saved
        #expect(saves.map(\.0) == [1, 2.2])
    }

    @Test func endedSavesFinalAndRequestsDismiss() async {
        let engine = FakeVideoPlayerEngine()
        var saves: [(Double, Double)] = []
        let model = makeModel(request: Fixture.request(), engine: engine, recorded: { _, _, p, d in saves.append((p, d)) })
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
                              recorded: { _, _, p, d in saves.append((p, d)) })
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.ended)); await model.waitForIdleForTesting()
        engine.emit(.state(.ended)); await model.waitForIdleForTesting()
        #expect(saves.count == 1)              // finish() guarded against the second .ended
        #expect(model.shouldDismiss == true)
    }

    @Test func teardownPersistsCurrentPosition() async {
        let engine = FakeVideoPlayerEngine()
        var saves: [(Double, Double)] = []
        let model = makeModel(request: Fixture.request(), engine: engine, recorded: { _, _, p, d in saves.append((p, d)) })
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
        // The downloaded track is the selected one, and it is NOT also listed as a generic
        // embedded pill (no duplicate "Track N" alongside the Hebrew row).
        let attached = model.attachedTrackID(model.subtitleRows.first { $0.language == "he" }!)
        #expect(attached != nil)
        #expect(model.selectedSubtitleID == attached)
        #expect(model.subtitleTracks.contains { $0.id == attached })
        #expect(!model.embeddedSubtitleTracks.contains { $0.id == attached })
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
        let model = makeModel(request: Fixture.request(), engine: engine, autoHideDelay: 0.05)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.playing)); await model.waitForIdleForTesting()
        #expect(model.controlsVisible == true)              // visible as playback starts
        // Poll up to ~1s for the auto-hide to fire (robust against scheduling jitter under load).
        for _ in 0..<50 where model.controlsVisible { try? await Task.sleep(nanoseconds: 20_000_000) }
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

    @Test func skipGivesOptimisticPositionAndBuffersUntilTimeResumes() async {
        // ±10s must feel instant: the bar jumps and a loading hint shows immediately, rather than
        // sitting on a black frame with no feedback until the engine reports the new time.
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 50, duration: 100))); await model.waitForIdleForTesting()
        #expect(model.hasRenderedFrame == true)
        model.skip(10)
        #expect(model.position == 60)            // bar jumps immediately
        #expect(model.isBuffering == true)       // loading hint while the seek rebuffers
        #expect(engine.seekedTo == 60)
        engine.emit(.time(.init(position: 60.6, duration: 100))); await model.waitForIdleForTesting()
        #expect(model.isBuffering == false)      // cleared once time advances again
    }

    @Test func skipClampsToZeroAndDuration() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 5, duration: 100))); await model.waitForIdleForTesting()
        model.skip(-30)
        #expect(model.position == 0)             // clamped at 0
        engine.emit(.time(.init(position: 0.1, duration: 100))); await model.waitForIdleForTesting()  // seek lands → guard settles
        engine.emit(.time(.init(position: 95, duration: 100))); await model.waitForIdleForTesting()
        model.skip(50)
        #expect(model.position == 100)           // clamped at duration
    }

    @Test func skipFeedbackAccumulatesAcrossABurstEvenAsSeeksLand() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 100, duration: 1000))); await model.waitForIdleForTesting()

        model.skip(10)
        #expect(model.skipFeedback?.seconds == 10)
        let firstID = model.skipFeedback?.id
        model.skip(10)
        #expect(model.skipFeedback?.seconds == 20)        // accumulates 10 → 20
        #expect(model.skipFeedback?.id != firstID)        // id bumps so the digits roll

        // A seek LANDS mid-burst. The counter must keep climbing (the old bug popped it back to 10),
        // because accumulation is tied to the on-screen badge, not the seek origin.
        engine.emit(.time(.init(position: 120, duration: 1000))); await model.waitForIdleForTesting()
        model.skip(10)
        #expect(model.skipFeedback?.seconds == 30)        // → 30, not reset
        model.skip(10)
        #expect(model.skipFeedback?.seconds == 40)        // → 40
    }

    @Test func skipFeedbackShowsTheClampedJumpAtTheEnds() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 95, duration: 100))); await model.waitForIdleForTesting()
        model.skip(10)                                    // only 5s of runway left
        #expect(model.skipFeedback?.seconds == 5)         // indicator shows the truthful 5, not 10
    }

    @Test func setVolumeClampsToBoostRangeAndDrivesTheEngine() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine)
        model.setVolume(150)
        #expect(model.volumePercent == 150)
        #expect(engine.volumesSet.last == 150)
        model.setVolume(500)                              // above the 200 boost ceiling
        #expect(model.volumePercent == 200)
        #expect(engine.volumesSet.last == 200)
    }

    @Test func aVolumeBoostIsReAssertedWhenTracksRefresh() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        model.setVolume(150)                              // one apply so far → [150]
        engine.audioTracks = [MediaTrack(id: "audio/0", kind: .audio, name: "English", language: "en")]
        engine.emit(.tracksChanged); await model.waitForIdleForTesting()
        // Re-asserted on the refresh → 150 applied at least twice (survives episode swap / async tracks).
        #expect(engine.volumesSet.filter { $0 == 150 }.count >= 2)
    }

    @Test func seekHoldsTargetThroughStalePreSeekTicks() async {
        // Bug #4: VLCKit keeps echoing the PRE-seek time for a tick or two after a seek is issued,
        // before the seek actually lands. Those stale ticks must NOT snap the scrub bar back to the
        // old spot — the displayed position holds at the target until a tick arrives near it.
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 100, duration: 2000))); await model.waitForIdleForTesting()
        #expect(model.position == 100)

        model.skip(1000)                                   // jump 100 → 1100
        #expect(model.position == 1100)                    // optimistic jump
        engine.emit(.time(.init(position: 101, duration: 2000))); await model.waitForIdleForTesting()
        #expect(model.position == 1100)                    // held at target — NOT snapped back to ~101
        engine.emit(.time(.init(position: 1100.4, duration: 2000))); await model.waitForIdleForTesting()
        #expect(model.position == 1100.4)                  // seek landed → live tracking resumes
        engine.emit(.time(.init(position: 1101, duration: 2000))); await model.waitForIdleForTesting()
        #expect(model.position == 1101)                    // continues advancing normally
    }

    @Test func backwardSeekHoldsTargetThroughStaleTicks() async {
        // Same as above but seeking backwards (commitScrub): the stale tick is now at a HIGHER
        // position than the target — it must not snap the bar forward either.
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 1500, duration: 2000))); await model.waitForIdleForTesting()
        model.beginScrub()
        model.updateScrub(by: -1000)                       // target 500
        #expect(model.scrubTarget == 500)
        model.commitScrub()
        #expect(model.position == 500)
        engine.emit(.time(.init(position: 1499, duration: 2000))); await model.waitForIdleForTesting()
        #expect(model.position == 500)                     // held — NOT snapped forward to ~1499
        engine.emit(.time(.init(position: 500.3, duration: 2000))); await model.waitForIdleForTesting()
        #expect(model.position == 500.3)                   // landed → resumes
    }

    @Test func midPlaybackBufferingShowsHintButKeepsVideoVisible() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 10, duration: 100))); await model.waitForIdleForTesting()
        #expect(model.phase == .playing)
        engine.emit(.state(.buffering)); await model.waitForIdleForTesting()
        #expect(model.phase == .playing)         // stays playing → the video isn't hidden
        #expect(model.isBuffering == true)       // …but the spinner shows
        engine.emit(.time(.init(position: 11, duration: 100))); await model.waitForIdleForTesting()
        #expect(model.isBuffering == false)
    }

    @Test func overlayHeldUntilFirstFrameAdvancesOnColdStart() async {
        // No resume: the full overlay stays until the first frame actually advances, so it never
        // hides over a still-black picture.
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        #expect(model.hasRenderedFrame == false)
        engine.emit(.state(.buffering)); await model.waitForIdleForTesting()
        #expect(model.hasRenderedFrame == false)  // buffering, no frames yet → overlay
        engine.emit(.time(.init(position: 2, duration: 100))); await model.waitForIdleForTesting()
        #expect(model.hasRenderedFrame == true)   // first advancing frame → overlay hides
        #expect(model.phase == .playing)
    }

    // MARK: - Next episode (binge)

    @Test func movieHasNoNextEpisode() async {
        let model = makeModel(request: Fixture.request(), engine: FakeVideoPlayerEngine())
        #expect(model.nextEpisode == nil)
        #expect(model.hasNextEpisode == false)
    }

    @Test func showExposesNextEpisodeUntilTheLast() async {
        let onE1 = makeModel(request: Fixture.showRequest(playingEpisode: 1), engine: FakeVideoPlayerEngine())
        #expect(onE1.nextEpisode?.number == 2)
        #expect(onE1.hasNextEpisode == true)
        let onE2 = makeModel(request: Fixture.showRequest(playingEpisode: 2), engine: FakeVideoPlayerEngine())
        #expect(onE2.nextEpisode == nil)                 // last episode → no next
    }

    @Test func playNextLoadsNextEpisodeSourceAndRetargetsLabel() async {
        let engine = FakeVideoPlayerEngine()
        var unrestricted: [String] = []
        let model = makeModel(request: Fixture.showRequest(playingEpisode: 1), engine: engine,
                              unrestrict: { link in unrestricted.append(link); return URL(string: "https://cdn/x.mkv")! })
        model.start(); await model.waitForIdleForTesting()
        #expect(unrestricted == ["rd://e1"])
        model.playNext(); await model.waitForIdleForTesting()
        #expect(unrestricted == ["rd://e1", "rd://e2"])  // the next episode's source loaded
        #expect(model.label == "The Show — S1·E2")
        #expect(model.nextEpisode == nil)                // now on the last episode
    }

    @Test func endedAutoAdvancesToNextEpisodeRecordingTheFinishedOne() async {
        let engine = FakeVideoPlayerEngine()
        var saves: [(String, Double)] = []               // (contentKey, position)
        let model = makeModel(request: Fixture.showRequest(playingEpisode: 1), engine: engine,
                              recorded: { key, _, p, _ in saves.append((key, p)) })
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 1400, duration: 1400))); await model.waitForIdleForTesting()
        engine.emit(.state(.ended)); await model.waitForIdleForTesting()
        #expect(model.shouldDismiss == false)            // did not dismiss — advanced instead
        #expect(model.label == "The Show — S1·E2")
        #expect(saves.contains { $0.1 == 1400 })         // finished episode's tail recorded before advancing
    }

    @Test func staleEndDuringEpisodeSwitchIsIgnored() async {
        // After an auto-advance loads the next episode (still loading, no frame yet), the OLD media
        // can emit a LATE `.ended`. Without a guard that stale end runs `finish()` again — exiting
        // the player (or skipping another episode) right after it advanced ("new one plays, then it
        // jumps/restarts"). The switch window must swallow it.
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.showRequest(playingEpisode: 1), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 1400, duration: 1400))); await model.waitForIdleForTesting()
        engine.emit(.state(.ended)); await model.waitForIdleForTesting()   // → advance to E2 (still loading)
        #expect(model.label == "The Show — S1·E2")
        engine.emit(.state(.ended)); await model.waitForIdleForTesting()   // stale end from E1's media
        #expect(model.label == "The Show — S1·E2")                         // still on E2
        #expect(model.shouldDismiss == false)                              // did NOT exit
    }

    @Test func endedOnLastEpisodeDismisses() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.showRequest(playingEpisode: 2), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.ended)); await model.waitForIdleForTesting()
        #expect(model.phase == .ended)
        #expect(model.shouldDismiss == true)             // no next episode → dismiss
    }

    // MARK: - Up Next bar

    @Test func upNextBarAppearsNearTheEndForAShowWithANextEpisode() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.showRequest(playingEpisode: 1), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.playing)); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 1300, duration: 1400))); await model.waitForIdleForTesting()
        #expect(model.upNextVisible == false)            // before the credits threshold (1400-30 = 1370)
        engine.emit(.time(.init(position: 1375, duration: 1400))); await model.waitForIdleForTesting()
        #expect(model.upNextVisible == true)
        #expect(model.upNextSecondsRemaining == 10)
    }

    @Test func upNextBarNeverAppearsForAMovie() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.playing)); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 1399, duration: 1400))); await model.waitForIdleForTesting()
        #expect(model.upNextVisible == false)            // no next episode → no bar
    }

    @Test func dismissUpNextHidesItAndTheFileEndExitsInsteadOfAdvancing() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.showRequest(playingEpisode: 1), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.playing)); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 1375, duration: 1400))); await model.waitForIdleForTesting()
        #expect(model.upNextVisible == true)
        model.dismissUpNext()
        #expect(model.upNextVisible == false)
        engine.emit(.state(.ended)); await model.waitForIdleForTesting()
        #expect(model.shouldDismiss == true)             // dismissed → exit at the real end
        #expect(model.label == "The Show — S1·E1")       // did NOT advance
    }

    @Test func playNextNowAdvancesImmediatelyAndResetsTheBar() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.showRequest(playingEpisode: 1), engine: engine)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.playing)); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 1375, duration: 1400))); await model.waitForIdleForTesting()
        #expect(model.upNextVisible == true)
        model.playNextNow(); await model.waitForIdleForTesting()
        #expect(model.label == "The Show — S1·E2")
        #expect(model.upNextVisible == false)            // reset for the new episode
    }

    @Test func upNextWaitsForTheCreditsNotAnEarlyLastLine() async throws {
        // The last subtitle cue ends at 16:42 (1002s) of a 2000s file, but the credits roll at the
        // END. The Up Next must NOT fire at the last line (the "starts the second the credits start /
        // too early" bug) — it appears in the last ~30s, proving the cue no longer triggers it directly.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).srt")
        try "1\n00:16:40,000 --> 00:16:42,000\nThe end.\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        subs.downloadedURL = url
        let model = makeModel(request: Fixture.showRequest(playingEpisode: 1), engine: engine, subtitles: subs)
        model.start(); await model.waitForIdleForTesting()
        await model.requestSubtitle(language: "he")
        engine.emit(.state(.playing)); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 1003, duration: 2000))); await model.waitForIdleForTesting()
        #expect(model.upNextVisible == false)            // last cue 1002 — must NOT fire there
        engine.emit(.time(.init(position: 1975, duration: 2000))); await model.waitForIdleForTesting()
        #expect(model.upNextVisible == true)             // appears in the credits (last ~30s)
    }

    @Test func upNextWaitsForDialogueRunningIntoTheCreditsZone() async throws {
        // Dialogue runs to 33:05 (1985s of a 2000s file), past the generic 30s-before-end mark (1970).
        // The cue is a FLOOR: the bar waits for the last line instead of firing over it.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).srt")
        try "1\n00:33:03,000 --> 00:33:05,000\nLast word.\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        subs.downloadedURL = url
        let model = makeModel(request: Fixture.showRequest(playingEpisode: 1), engine: engine, subtitles: subs)
        model.start(); await model.waitForIdleForTesting()
        await model.requestSubtitle(language: "he")
        engine.emit(.state(.playing)); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 1972, duration: 2000))); await model.waitForIdleForTesting()
        #expect(model.upNextVisible == false)            // a line is still being spoken (1985) — wait
        engine.emit(.time(.init(position: 1986, duration: 2000))); await model.waitForIdleForTesting()
        #expect(model.upNextVisible == true)
    }

    // MARK: - Track preferences (persist audio/subtitle choice by language)

    private func audioPair() -> [MediaTrack] {
        [MediaTrack(id: "audio/0", kind: .audio, name: "English", language: "en"),
         MediaTrack(id: "audio/1", kind: .audio, name: "Hebrew", language: "he")]
    }

    @Test func recordsAudioLanguageWhenUserSelects() async {
        let engine = FakeVideoPlayerEngine()
        let prefs = FakeTrackPreferences()
        let model = makeModel(request: Fixture.request(), engine: engine, trackPreferences: prefs)
        model.start(); await model.waitForIdleForTesting()
        engine.audioTracks = audioPair()
        engine.emit(.tracksChanged); await model.waitForIdleForTesting()
        model.selectAudio(id: "audio/1")
        #expect(prefs.preferredAudio == .language("he"))     // remembered by language, not the raw id
    }

    @Test func recordsSubtitleLanguageOnSelectAndOffOnSelectOff() async {
        let engine = FakeVideoPlayerEngine()
        let prefs = FakeTrackPreferences()
        let model = makeModel(request: Fixture.request(), engine: engine, trackPreferences: prefs)
        model.start(); await model.waitForIdleForTesting()
        engine.audioTracks = audioPair()
        engine.subtitleTracks = [MediaTrack(id: "spu/0", kind: .subtitle, name: "English", language: "en")]
        engine.emit(.tracksChanged); await model.waitForIdleForTesting()
        model.selectSubtitle(id: "spu/0")
        #expect(prefs.preferredSubtitle == .language("en"))
        model.selectSubtitleOff()
        #expect(prefs.preferredSubtitle == .off)             // explicit Off persists (≠ automatic)
    }

    @Test func autoAppliesPreferredAudioLanguageWhenTracksLoad() async {
        let engine = FakeVideoPlayerEngine()
        let prefs = FakeTrackPreferences(audio: .language("he"))
        let model = makeModel(request: Fixture.request(), engine: engine, trackPreferences: prefs)
        model.start(); await model.waitForIdleForTesting()
        engine.audioTracks = audioPair()
        engine.emit(.tracksChanged); await model.waitForIdleForTesting()
        #expect(engine.selectedAudioID == .some("audio/1"))  // Hebrew selected automatically
        #expect(model.selectedAudioID == "audio/1")
    }

    @Test func autoAppliesSubtitleOffWhenPreferred() async {
        let engine = FakeVideoPlayerEngine()
        let prefs = FakeTrackPreferences(subtitle: .off)
        let model = makeModel(request: Fixture.request(), engine: engine, trackPreferences: prefs)
        model.start(); await model.waitForIdleForTesting()
        engine.audioTracks = audioPair()
        engine.subtitleTracks = [MediaTrack(id: "spu/0", kind: .subtitle, name: "English", language: "en")]
        engine.emit(.tracksChanged); await model.waitForIdleForTesting()
        #expect(engine.selectedSubtitleID == .some(nil))     // explicitly turned off
        #expect(model.selectedSubtitleID == nil)
    }

    @Test func autoSelectsEmbeddedPreferredSubtitleLanguage() async {
        let engine = FakeVideoPlayerEngine()
        let prefs = FakeTrackPreferences(subtitle: .language("he"))
        let model = makeModel(request: Fixture.request(), engine: engine, trackPreferences: prefs)
        model.start(); await model.waitForIdleForTesting()
        engine.audioTracks = audioPair()
        engine.subtitleTracks = [MediaTrack(id: "spu/0", kind: .subtitle, name: "English", language: "en"),
                                 MediaTrack(id: "spu/1", kind: .subtitle, name: "Hebrew", language: "he")]
        engine.emit(.tracksChanged); await model.waitForIdleForTesting()
        #expect(engine.selectedSubtitleID == .some("spu/1"))
        #expect(model.selectedSubtitleID == "spu/1")
    }

    @Test func autoDownloadsPreferredSubtitleWhenNotEmbedded() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        subs.downloadedURL = URL(fileURLWithPath: "/tmp/he.srt")
        let prefs = FakeTrackPreferences(subtitle: .language("he"))
        let model = makeModel(request: Fixture.request(), engine: engine, subtitles: subs, trackPreferences: prefs)
        model.start(); await model.waitForIdleForTesting()
        engine.audioTracks = audioPair()
        engine.subtitleTracks = []                           // no embedded Hebrew
        engine.emit(.tracksChanged); await model.waitForIdleForTesting()
        await model.waitForIdleForTesting()
        #expect(subs.searchedLanguages.contains(["he"]))     // auto-kicked a Hebrew download
    }

    @Test func autoDownloadHappensOncePerSource() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        subs.downloadedURL = URL(fileURLWithPath: "/tmp/he.srt")
        let prefs = FakeTrackPreferences(subtitle: .language("he"))
        let model = makeModel(request: Fixture.request(), engine: engine, subtitles: subs, trackPreferences: prefs)
        model.start(); await model.waitForIdleForTesting()
        engine.audioTracks = audioPair()
        engine.emit(.tracksChanged); await model.waitForIdleForTesting()
        await model.waitForIdleForTesting()
        engine.emit(.tracksChanged); await model.waitForIdleForTesting()   // VLCKit re-fires
        #expect(subs.searchedLanguages.filter { $0 == ["he"] }.count == 1) // applied once, not per event
    }

    @Test func manualSubtitleDownloadRecordsLanguagePreference() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        subs.downloadedURL = URL(fileURLWithPath: "/tmp/he.srt")
        let prefs = FakeTrackPreferences()
        let model = makeModel(request: Fixture.request(), engine: engine, subtitles: subs, trackPreferences: prefs)
        model.start(); await model.waitForIdleForTesting()
        await model.requestSubtitle(language: "he")
        #expect(prefs.preferredSubtitle == .language("he"))  // the first manual pick becomes sticky
    }

    @Test func noTrackPreferenceStoreLeavesSelectionUntouched() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine)   // no prefs store
        model.start(); await model.waitForIdleForTesting()
        engine.audioTracks = audioPair()
        engine.emit(.tracksChanged); await model.waitForIdleForTesting()
        #expect(engine.selectedAudioID == nil)               // nothing auto-applied
    }

    // MARK: - Authoritative resume (the store, not the screen's possibly-stale watch state)

    @Test func resumeProviderOverridesTheRequestHint() async {
        // The screen built the request with a stale hint; the store's saved position wins.
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(resumeAt: 615), engine: engine,
                              resolveResume: { _ in 300 })
        model.start(); await model.waitForIdleForTesting()
        #expect(engine.seeks == [300])                       // store's truth, not the hint
        engine.emit(.time(.init(position: 300.2, duration: 1000))); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 300.9, duration: 1000))); await model.waitForIdleForTesting()
        #expect(model.phase == .playing)
    }

    @Test func resumeProviderFixesThePlayBeforeWatchStateLoadedRace() async {
        // THE bug: tap Play right after Detail opens → the request carries resumeAt nil because
        // watch state hadn't loaded. The provider must still resume from the saved position.
        let engine = FakeVideoPlayerEngine()
        var asked: [String] = []
        let model = makeModel(request: Fixture.request(resumeAt: nil), engine: engine,
                              resolveResume: { key in asked.append(key); return 500 })
        model.start(); await model.waitForIdleForTesting()
        #expect(asked == ["m1"])                             // resolved for the movie's contentKey
        #expect(engine.seeks == [500])                       // resumed despite the nil hint
    }

    @Test func fromStartNeverConsultsTheProviderOrSeeks() async {
        // Explicit "Start over" must win over any saved position.
        let engine = FakeVideoPlayerEngine()
        var asked = 0
        let model = makeModel(request: Fixture.request(resumeAt: nil, fromStart: true), engine: engine,
                              resolveResume: { _ in asked += 1; return 500 })
        model.start(); await model.waitForIdleForTesting()
        #expect(asked == 0)                                  // provider not even consulted
        #expect(engine.seeks.isEmpty)                        // plays from 0
    }

    @Test func retryReResolvesResumeSoPlaybackContinuesWhereItFailed() async {
        // Progress saved during playback + a provider re-read on reload → a retry (or
        // try-another-version) resumes near the failure point instead of starting over.
        let engine = FakeVideoPlayerEngine()
        var saved: Double? = nil
        let model = makeModel(request: Fixture.request(), engine: engine,
                              resolveResume: { _ in saved })
        model.start(); await model.waitForIdleForTesting()
        #expect(engine.seeks.isEmpty)                        // nothing saved yet → from the start
        saved = 44                                           // playback progressed, then failed
        engine.emit(.state(.failed("boom"))); await model.waitForIdleForTesting()
        model.retry(); await model.waitForIdleForTesting()
        #expect(engine.seeks == [44])                        // resumed where it failed
    }

    @Test func finishedElsewhereMeansStartFromZeroDespiteAHint() async {
        // Watched to the end on another device (provider says 0/finished) — the stale local
        // hint must not drag playback to the old position.
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(resumeAt: 615), engine: engine,
                              resolveResume: { _ in 0 })
        model.start(); await model.waitForIdleForTesting()
        #expect(engine.seeks.isEmpty)                        // authoritative 0 → no resume seek
    }

    @Test func episodeSwitchResolvesResumeForTheNewEpisodesKey() async {
        // Auto-advance / strip picks resume the NEW episode when it was partially watched.
        let engine = FakeVideoPlayerEngine()
        var asked: [String] = []
        let request = Fixture.showRequest(playingEpisode: 1)
        let e2 = request.item.seasons[0].episodes[1]
        let e2Key = WatchKey.content(forShow: request.item, episode: e2)
        let model = makeModel(request: request, engine: engine,
                              resolveResume: { key in asked.append(key); return key == e2Key ? 120 : nil })
        model.start(); await model.waitForIdleForTesting()
        #expect(engine.seeks.isEmpty)                        // E1 has no saved position
        model.playNext(); await model.waitForIdleForTesting()
        #expect(asked.count == 2)                            // re-resolved for the new episode
        #expect(engine.seeks == [120])                       // E2 resumes at its own position
    }

    // MARK: - Seek coalescing (rapid skips)

    @Test func rapidSkipsCoalesceIntoLeadingAndTrailingEngineSeeks() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine, seekCoalesceWindow: 0.08)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 50, duration: 1000))); await model.waitForIdleForTesting()
        model.skip(10); model.skip(10); model.skip(10); model.skip(10)
        #expect(model.position == 90)                        // bar reflects all four immediately
        #expect(engine.seeks == [60])                        // leading seek only — burst still open
        for _ in 0..<40 where engine.seeks.count < 2 {       // wait out the window
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(engine.seeks == [60, 90])                    // one trailing seek at the final target
    }

    @Test func slowSkipsEachSeekImmediately() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine, seekCoalesceWindow: 0.03)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 50, duration: 1000))); await model.waitForIdleForTesting()
        model.skip(10)
        try? await Task.sleep(nanoseconds: 60_000_000)       // past the window
        model.skip(10)
        #expect(engine.seeks == [60, 70])                    // two isolated skips → two leading seeks
    }

    @Test func skipBurstHoldsTheBarAgainstStaleTicksFromTheOriginalOrigin() async {
        // Mid-burst stale engine echoes near the ORIGINAL origin must not snap the bar back,
        // even though the displayed position has stacked several skips since.
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine, seekCoalesceWindow: 0.08)
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 100, duration: 2000))); await model.waitForIdleForTesting()
        model.skip(100); model.skip(100)                     // 100 → 300 optimistically
        #expect(model.position == 300)
        engine.emit(.time(.init(position: 101, duration: 2000))); await model.waitForIdleForTesting()
        #expect(model.position == 300)                       // stale echo near origin → held
        engine.emit(.time(.init(position: 299.5, duration: 2000))); await model.waitForIdleForTesting()
        #expect(model.position == 299.5)                     // landed near the target → live again
    }

    // MARK: - Up Next prefetch (binge warm-up)

    @Test func upNextAppearingPrefetchesTheNextEpisodesLink() async {
        let engine = FakeVideoPlayerEngine()
        var prefetched: [String] = []
        let model = makeModel(request: Fixture.showRequest(playingEpisode: 1), engine: engine,
                              prefetchLink: { prefetched.append($0) })
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.playing)); await model.waitForIdleForTesting()
        #expect(prefetched.isEmpty)
        engine.emit(.time(.init(position: 1375, duration: 1400))); await model.waitForIdleForTesting()
        #expect(model.upNextVisible == true)
        #expect(prefetched == ["rd://e2"])                   // warmed as the bar appeared
    }
}
