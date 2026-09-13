import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// Syncing a subtitle to a line the viewer can hear.
///
/// The measurement a person can make that the machine cannot is "that line was spoken NOW". It is
/// only worth anything if the press can be timestamped accurately, which is why the engine is asked
/// for the time rather than the once-a-second tick being trusted.
@MainActor
@Suite struct PlayerManualSyncTests {

    private func model(engine: FakeVideoPlayerEngine = FakeVideoPlayerEngine()) -> PlayerModel {
        PlayerModel(request: Fixture.request(sources: [Fixture.movieSource()]), engine: engine,
                    unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _ in }, subtitles: FakeSubtitleProvider())
    }

    @Test func theEnginesOwnClockIsPreferredToTheTick() {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine: engine)
        m.position = 120                 // the once-a-second tick
        engine.preciseTime = 120.64      // where the film actually is

        #expect(m.preciseNow == 120.64)
    }

    @Test func theTickIsTheFallbackWhenTheEngineCannotAnswer() {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine: engine)
        m.position = 120
        engine.preciseTime = nil

        #expect(m.preciseNow == 120)
    }

    // MARK: - The lines to press against

    /// Download a Hebrew subtitle and let the fake engine surface it as a slave track, which is
    /// what `attachedSubtitleTracks` keys the cue list by.
    ///
    /// The start → idle → request → idle sequence is exactly what `PlayerAutoSyncProgressTests`
    /// uses; `requestSubtitle` is the public entry point (`downloadSubtitle` is private and cannot
    /// be reached from a test, `@testable` or not).
    private func modelWithDownloadedSubtitle(
        _ srt: String,
        engine: FakeVideoPlayerEngine = FakeVideoPlayerEngine()
    ) async -> PlayerModel {
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        subs.downloadedText = srt
        let m = PlayerModel(request: Fixture.request(sources: [Fixture.movieSource()]),
                            engine: engine, unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _ in }, subtitles: subs)
        m.start()
        await m.waitForIdleForTesting()
        await m.requestSubtitle(language: "he")
        await m.waitForIdleForTesting()
        m.setDurationForTesting(900)
        return m
    }

    private static let twoLines = """
    1
    00:00:10,000 --> 00:00:12,000
    First line.

    2
    00:00:20,000 --> 00:00:22,000
    Second line.

    """

    @Test func anAttachedDownloadCarriesItsLines() async {
        let m = await modelWithDownloadedSubtitle(Self.twoLines)

        #expect(m.canManualSync)
        #expect(m.manualSyncCues.map(\.text) == ["First line.", "Second line."])
    }

    @Test func aMuxedTrackCannotBeSyncedByHand() {
        // Nothing downloaded: the selected track, if any, is one inside the container, and no cue
        // list exists for it to be measured against.
        let m = model()

        #expect(!m.canManualSync)
        #expect(m.manualSyncCues.isEmpty)
    }

    @Test func aSubtitleWithNoReadableLinesCannotBeSyncedByHand() async {
        let m = await modelWithDownloadedSubtitle("not a subtitle file at all\n")

        #expect(!m.canManualSync)
    }
}
