import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// A downloaded subtitle is moved by rewriting its cue times, not through libvlc's delay.
///
/// libvlc drops any line it is asked to show more than a few seconds before it has read it, so the
/// offsets a late subtitle needs (−10s and beyond on the Apple TV) made every line vanish. These
/// pin the replacement: the offset lives in an attached copy of the file, and libvlc is sent none.
@MainActor
@Suite struct PlayerSubtitleShiftTests {

    private static let twoLines = """
    1
    00:00:10,000 --> 00:00:12,000
    First line.

    2
    00:00:20,000 --> 00:00:22,000
    Second line.

    """

    private func modelWithDownloadedSubtitle(
        engine: FakeVideoPlayerEngine,
        prefs: FakeTrackPreferences? = nil
    ) async -> PlayerModel {
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        subs.downloadedText = Self.twoLines
        let m = PlayerModel(request: Fixture.request(sources: [Fixture.movieSource()]),
                            engine: engine, unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _, _ in }, subtitles: subs,
                            trackPreferences: prefs, subtitleShiftDebounce: 0.05)
        m.start()
        await m.waitForIdleForTesting()
        await m.requestSubtitle(language: "he")
        await m.waitForIdleForTesting()
        return m
    }

    /// Wait out the debounce and let the re-attach land.
    private func settle(_ m: PlayerModel) async {
        try? await Task.sleep(for: .milliseconds(200))
        await m.waitForIdleForTesting()
    }

    private func text(of url: URL?) -> String {
        url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    @Test func pullingADownloadedSubtitleEarlierMovesTheLinesInTheFile() async {
        let engine = FakeVideoPlayerEngine()
        let m = await modelWithDownloadedSubtitle(engine: engine)
        let original = m.selectedSubtitleID

        m.adjustSubtitleDelay(by: -11.5)
        await settle(m)

        // A second file went to the engine, carrying the offset in its cue times…
        #expect(engine.addedSubtitles.count == 2)
        #expect(text(of: engine.addedSubtitles.last).contains("00:00:08,500 --> 00:00:10,500"))
        // …it is the one on screen…
        #expect(m.selectedSubtitleID != original)
        #expect(engine.selectedSubtitleID == m.selectedSubtitleID)
        // …and libvlc was never asked to move anything earlier.
        #expect(engine.subtitleDelays.allSatisfy { $0 >= 0 })
        #expect(m.subtitleDelay == -11.5)
    }

    @Test func aHeldNudgeButtonIsOneReattach() async {
        let engine = FakeVideoPlayerEngine()
        let m = await modelWithDownloadedSubtitle(engine: engine)

        for _ in 0..<20 { m.adjustSubtitleDelay(by: -0.5) }
        await settle(m)

        #expect(engine.addedSubtitles.count == 2)             // the download, then ONE copy
        #expect(text(of: engine.addedSubtitles.last).contains("00:00:10,000 --> 00:00:12,000\nSecond"))
    }

    @Test func resetPutsTheFileAsDownloadedBackWithoutAnotherAttach() async {
        let engine = FakeVideoPlayerEngine()
        let m = await modelWithDownloadedSubtitle(engine: engine)
        let original = m.selectedSubtitleID
        m.adjustSubtitleDelay(by: -2)
        await settle(m)

        m.resetSubtitleDelay()
        await settle(m)

        #expect(m.selectedSubtitleID == original)
        #expect(engine.selectedSubtitleID == original)
        #expect(engine.addedSubtitles.count == 2)              // nothing new: re-selected
    }

    @Test func returningToAnOffsetReusesItsCopy() async {
        // libvlc will not attach the same file twice, so a copy made before must be re-selected.
        let engine = FakeVideoPlayerEngine()
        let m = await modelWithDownloadedSubtitle(engine: engine)
        m.applySubtitleDelay(-2); await settle(m)
        let atMinusTwo = m.selectedSubtitleID
        m.applySubtitleDelay(-3); await settle(m)

        m.applySubtitleDelay(-2); await settle(m)

        #expect(m.selectedSubtitleID == atMinusTwo)
        #expect(engine.addedSubtitles.count == 3)              // download, −2, −3 — and no more
    }

    @Test func theSyncToolsStillSeeTheSubtitleAsDownloaded() async {
        // A hand sync measures against the subtitle's OWN cue times, and the offset is remembered
        // under the downloaded file's name — neither may start describing the shifted copy.
        let engine = FakeVideoPlayerEngine()
        let prefs = FakeTrackPreferences()
        let m = await modelWithDownloadedSubtitle(engine: engine, prefs: prefs)
        let downloaded = engine.addedSubtitles.first!.lastPathComponent

        m.applySubtitleDelay(-4)
        await settle(m)

        #expect(m.canManualSync)
        #expect(m.manualSyncCues.map(\.start) == [10, 20])
        #expect(prefs.recordedSubtitleDelays.keys.allSatisfy { $0.hasSuffix("|\(downloaded)") })
        #expect(prefs.recordedSubtitleDelays.values.contains(-4))
    }

    @Test func oldCopiesNeverShowUpAsLooseTracks() async {
        let engine = FakeVideoPlayerEngine()
        let m = await modelWithDownloadedSubtitle(engine: engine)
        m.applySubtitleDelay(-2); await settle(m)
        m.applySubtitleDelay(-5); await settle(m)

        // Three slaves now sit in the engine's list; every one of them is ours.
        #expect(engine.subtitleTracks.filter(\.isExternal).count == 3)
        #expect(m.embeddedSubtitleTracks.allSatisfy { !$0.isExternal })
    }

    @Test func aBuiltInTrackStillTakesTheOffsetThroughTheEngine() {
        let engine = FakeVideoPlayerEngine()
        engine.subtitleTracks = [MediaTrack(id: "spu/3", kind: .subtitle, name: "English",
                                            language: "en")]
        let m = PlayerModel(request: Fixture.request(), engine: engine,
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _, _ in }, subtitles: nil)
        m.subtitleTracks = engine.subtitleTracks
        m.selectSubtitle(id: "spu/3")

        m.applySubtitleDelay(-2)
        #expect(engine.subtitleDelays.last == -2)
        #expect(!m.subtitleOffsetBeyondEmbeddedReach)

        // Past what libvlc can show, the panel is told why the lines are gone.
        m.applySubtitleDelay(-5)
        #expect(m.subtitleOffsetBeyondEmbeddedReach)
        #expect(engine.addedSubtitles.isEmpty)                 // no file to rewrite, none invented
    }
}
