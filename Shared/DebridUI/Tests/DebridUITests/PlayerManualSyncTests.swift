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

    // MARK: - The measurement

    @Test func pressingOnALineMeasuresTheOffsetFromIt() async {
        let engine = FakeVideoPlayerEngine()
        let m = await modelWithDownloadedSubtitle(Self.twoLines, engine: engine)
        m.beginManualSync()
        // The first line is authored at 10s and was actually heard at 12.4s.
        engine.preciseTime = 12.4

        m.markSyncMoment()

        #expect(abs(m.subtitleDelay - 2.4) < 0.0001)
        #expect(engine.subtitleDelays.last.map { abs($0 - 2.4) < 0.0001 } == true)
    }

    @Test func theLineNearestThePlayheadIsSelectedFirst() async {
        let m = await modelWithDownloadedSubtitle(Self.twoLines)
        m.position = 20.5                      // inside the second cue

        m.beginManualSync()

        #expect(m.manualSyncReadout?.selected.text == "Second line.")
    }

    /// The point of the whole design: the press records a moment, and which line it was stays
    /// changeable afterwards. Reacting to a line you have heard is something a person can do
    /// accurately; predicting one you have not is not.
    @Test func movingTheLineAfterThePressRecomputesFromTheSameMoment() async {
        let engine = FakeVideoPlayerEngine()
        let m = await modelWithDownloadedSubtitle(Self.twoLines, engine: engine)
        m.beginManualSync()
        engine.preciseTime = 12.4
        m.markSyncMoment()
        #expect(abs(m.subtitleDelay - 2.4) < 0.0001)

        // It was the SECOND line that was heard, not the first: 12.4 − 20 = −7.6.
        engine.preciseTime = 999                // must not be re-read
        m.moveSyncLine(by: 1)

        #expect(abs(m.subtitleDelay - -7.6) < 0.0001)
        #expect(m.manualSyncReadout?.selected.text == "Second line.")
    }

    @Test func movingTheLineBeforeAnyPressChangesNothingYet() async {
        let engine = FakeVideoPlayerEngine()
        let m = await modelWithDownloadedSubtitle(Self.twoLines, engine: engine)
        m.beginManualSync()

        m.moveSyncLine(by: 1)

        #expect(m.subtitleDelay == 0)
        #expect(m.manualSyncReadout?.offset == nil)
        #expect(engine.subtitleDelays.isEmpty)
    }

    @Test func theSelectionCannotRunOffEitherEndOfTheList() async {
        let m = await modelWithDownloadedSubtitle(Self.twoLines)
        m.beginManualSync()

        m.moveSyncLine(by: -5)
        #expect(m.manualSyncReadout?.selected.text == "First line.")

        m.moveSyncLine(by: 99)
        #expect(m.manualSyncReadout?.selected.text == "Second line.")
    }

    @Test func aSecondPressReplacesTheFirst() async {
        let engine = FakeVideoPlayerEngine()
        let m = await modelWithDownloadedSubtitle(Self.twoLines, engine: engine)
        m.beginManualSync()
        engine.preciseTime = 12.4
        m.markSyncMoment()

        engine.preciseTime = 11.0
        m.markSyncMoment()

        #expect(abs(m.subtitleDelay - 1.0) < 0.0001)
    }

    /// The engine is pushed `subtitleDelay + subtitleDriftDelay`. Measure without subtracting the
    /// drift and a hand sync on a PAL-corrected subtitle lands wrong by however far the correction
    /// has already grown.
    @Test func theDriftCorrectionIsSubtractedOutOfTheMeasurement() async {
        let engine = FakeVideoPlayerEngine()
        engine.videoFPS = 23.976
        let m = await modelWithDownloadedSubtitle(Self.twoLines, engine: engine)
        m.position = 1000
        m.setSubtitleSourceFPS(25)             // arms the running drift correction
        let drift = m.subtitleDriftDelay
        #expect(drift > 0)                     // the fixture must actually exercise the term

        m.beginManualSync()
        m.moveSyncLine(by: -5)                 // onto the first line, wherever the playhead landed
        engine.preciseTime = 12.4
        m.markSyncMoment()

        #expect(abs(m.subtitleDelay - (12.4 - 10 - drift)) < 0.0001)
    }

    /// …and the drift used is the one captured at the press. Recomputing it when the viewer moves
    /// the line minutes later would shift an answer that was already right.
    @Test func movingTheLineUsesTheDriftFromThePressNotFromNow() async {
        let engine = FakeVideoPlayerEngine()
        engine.videoFPS = 23.976
        let m = await modelWithDownloadedSubtitle(Self.twoLines, engine: engine)
        m.position = 1000
        m.setSubtitleSourceFPS(25)
        let driftAtPress = m.subtitleDriftDelay
        m.beginManualSync()
        m.moveSyncLine(by: -5)                 // start on the first line
        engine.preciseTime = 12.4
        m.markSyncMoment()

        m.position = 4000                      // the film has moved on; the drift has grown
        m.moveSyncLine(by: 1)                  // …now the second line, at 20s

        #expect(m.subtitleDriftDelay > driftAtPress)     // the live value really did move
        #expect(abs(m.subtitleDelay - (12.4 - 20 - driftAtPress)) < 0.0001)
    }

    @Test func aWildlyWrongLineIsClampedRatherThanAccepted() async {
        let engine = FakeVideoPlayerEngine()
        let m = await modelWithDownloadedSubtitle(Self.twoLines, engine: engine)
        m.beginManualSync()
        engine.preciseTime = 100_000

        m.markSyncMoment()

        #expect(m.subtitleDelay == PlayerModel.maxSubtitleDelay)
    }

    @Test func nudgingMovesTheOffsetAndShowsInTheReadout() async {
        let engine = FakeVideoPlayerEngine()
        let m = await modelWithDownloadedSubtitle(Self.twoLines, engine: engine)
        m.beginManualSync()
        engine.preciseTime = 12.4
        m.markSyncMoment()

        m.nudgeSyncOffset(by: -0.1)

        #expect(abs(m.subtitleDelay - 2.3) < 0.0001)
        #expect(m.manualSyncReadout?.offset.map { abs($0 - 2.3) < 0.0001 } == true)
    }

    @Test func thereIsNoSessionWithoutASubtitleToSyncTo() {
        let m = model()

        m.beginManualSync()

        #expect(m.manualSyncReadout == nil)
    }

    @Test func endingTheSessionLeavesTheOffsetInPlace() async {
        let engine = FakeVideoPlayerEngine()
        let m = await modelWithDownloadedSubtitle(Self.twoLines, engine: engine)
        m.beginManualSync()
        engine.preciseTime = 12.4
        m.markSyncMoment()

        m.endManualSync()

        #expect(m.manualSyncReadout == nil)
        #expect(abs(m.subtitleDelay - 2.4) < 0.0001)   // closing the panel is not undoing the work
    }

    @Test func theReadoutShowsTheNeighboursOfTheSelectedLine() async {
        let srt = (0..<6).map { i in
            "\(i + 1)\n00:00:\(String(format: "%02d", i * 10)),000 --> " +
            "00:00:\(String(format: "%02d", i * 10 + 2)),000\nLine \(i)\n"
        }.joined(separator: "\n")
        let m = await modelWithDownloadedSubtitle(srt)
        m.position = 30                        // the fourth cue
        m.beginManualSync()

        #expect(m.manualSyncReadout?.lines.map(\.text) == ["Line 1", "Line 2", "Line 3",
                                                          "Line 4", "Line 5"])
        #expect(m.manualSyncReadout?.selected.text == "Line 3")
    }

    // MARK: - Remembering

    /// Takes the provider rather than making one, because the fake names its file per INSTANCE.
    /// Two sittings on the same film pull the same cached subtitle in production — the download
    /// cache names files by OpenSubtitles `file_id` — so a test about restoring has to share one.
    private func modelWithPreferences(
        _ prefs: FakeTrackPreferences,
        subs: FakeSubtitleProvider,
        engine: FakeVideoPlayerEngine = FakeVideoPlayerEngine()
    ) async -> PlayerModel {
        let m = PlayerModel(request: Fixture.request(sources: [Fixture.movieSource()]),
                            engine: engine, unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _ in }, subtitles: subs,
                            trackPreferences: prefs)
        m.start()
        await m.waitForIdleForTesting()
        await m.requestSubtitle(language: "he")
        await m.waitForIdleForTesting()
        m.setDurationForTesting(900)
        return m
    }

    private func hebrewProvider(_ srt: String = twoLines) -> FakeSubtitleProvider {
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        subs.downloadedText = srt
        return subs
    }

    @Test func aHandSyncIsRememberedAgainstThisFileAndThisSubtitle() async {
        let prefs = FakeTrackPreferences()
        let engine = FakeVideoPlayerEngine()
        let m = await modelWithPreferences(prefs, subs: hebrewProvider(), engine: engine)
        m.beginManualSync()
        engine.preciseTime = 12.4

        m.markSyncMoment()

        let file = m.selectedDownloadedSubtitleFile!.lastPathComponent
        let saved = prefs.subtitleDelay(forSource: Fixture.sourceKey, subtitle: file)
        #expect(saved.map { abs($0 - 2.4) < 0.0001 } == true)
    }

    @Test func aRememberedOffsetIsRestoredWhenTheSameSubtitleIsAttachedAgain() async {
        let prefs = FakeTrackPreferences()
        let subs = hebrewProvider()
        // What the first sitting left behind.
        let first = await modelWithPreferences(prefs, subs: subs)
        let file = first.selectedDownloadedSubtitleFile!.lastPathComponent
        prefs.recordedSubtitleDelays["\(Fixture.sourceKey)|\(file)"] = 3.5

        let second = await modelWithPreferences(prefs, subs: subs)

        #expect(second.subtitleDelay == 3.5)
    }

    @Test func anOffsetIsNotRestoredForADifferentSubtitleFile() async {
        let prefs = FakeTrackPreferences()
        prefs.recordedSubtitleDelays["\(Fixture.sourceKey)|some-other-subtitle.srt"] = 3.5

        let m = await modelWithPreferences(prefs, subs: hebrewProvider())

        #expect(m.subtitleDelay == 0)
    }

    @Test func resettingTheTimingForgetsTheOffset() async {
        let prefs = FakeTrackPreferences()
        let engine = FakeVideoPlayerEngine()
        let m = await modelWithPreferences(prefs, subs: hebrewProvider(), engine: engine)
        m.beginManualSync()
        engine.preciseTime = 12.4
        m.markSyncMoment()
        let file = m.selectedDownloadedSubtitleFile!.lastPathComponent

        m.resetSubtitleDelay()

        #expect(prefs.subtitleDelay(forSource: Fixture.sourceKey, subtitle: file) == nil)
    }

    /// A muxed track has no file to key an offset by, so nudging one must not write anything —
    /// least of all under a key that would later be restored onto a different subtitle.
    @Test func anOffsetOnAMuxedTrackIsNotRemembered() {
        let prefs = FakeTrackPreferences()
        let m = PlayerModel(request: Fixture.request(sources: [Fixture.movieSource()]),
                            engine: FakeVideoPlayerEngine(),
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _ in }, subtitles: FakeSubtitleProvider(),
                            trackPreferences: prefs)

        m.adjustSubtitleDelay(by: 1.5)

        #expect(prefs.recordedSubtitleDelays.isEmpty)
    }

    // MARK: - Not being overwritten by the automatic path

    /// Observed from INSIDE the measurement, not from the model's own bookkeeping: the task handle
    /// is dropped either way, so asserting it went nil would pass against code that never cancelled
    /// anything. What matters is that the work in flight learns it has been abandoned.
    @Test func startingAHandSyncCancelsARunningMeasurement() async {
        let probe = GatedProbe(FakeAudioProbe.speaking(at: Self.syncCueTimes))
        let m = await modelForCollision(probe)
        m.startAutoSync()
        await m.settleForTesting()
        #expect(m.autoSyncTask != nil)

        m.beginManualSync()
        probe.finish()
        await m.settleForTesting()

        #expect(probe.sawCancellation == true)
    }

    /// Cancellation is cooperative: the measurement's result is already in hand by the time the
    /// await returns, so without a guard at the apply site it would move a subtitle the viewer
    /// has just dialled in themselves — minutes after they stopped looking.
    @Test func aCancelledMeasurementDoesNotLandOnTopOfAHandSync() async {
        let engine = FakeVideoPlayerEngine()
        // The audio has every line 4s EARLIER than the subtitle claims, so an uncancelled
        // measurement would apply about −4s — a value nothing else in this test could produce.
        let probe = GatedProbe(FakeAudioProbe.speaking(at: Self.syncCueTimes.map { $0 - 4 }))
        let m = await modelForCollision(probe, engine: engine)
        m.startAutoSync()
        await m.settleForTesting()

        // The viewer answers by hand while the measurement is still held mid-flight.
        m.beginManualSync()
        engine.preciseTime = Self.syncCueTimes[0] + 2.5
        m.markSyncMoment()
        let byHand = m.subtitleDelay
        #expect(abs(byHand - 2.5) < 0.0001)

        probe.finish()                         // …and the measurement returns anyway
        await m.settleForTesting()

        #expect(m.subtitleDelay == byHand)   // untouched, to the bit
    }

    private func modelForCollision(_ probe: AudioLoudnessProbing,
                                   engine: FakeVideoPlayerEngine = FakeVideoPlayerEngine())
    async -> PlayerModel {
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        subs.downloadedText = Self.syncSRT
        let m = PlayerModel(request: Fixture.request(sources: [Fixture.movieSource()]),
                            engine: engine, unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _ in }, subtitles: subs, audioProbe: probe,
                            autoSyncWindow: 90, autoSyncMaxLag: 5, autoSyncMinimumHalf: 25)
        m.start()
        await m.waitForIdleForTesting()
        await m.requestSubtitle(language: "he")
        await m.waitForIdleForTesting()
        m.setDurationForTesting(900)
        return m
    }

    /// Holds a real probe mid-flight so the collision with a hand sync can be staged rather than
    /// raced. Releasing it afterwards is what proves the late result is refused.
    final class GatedProbe: AudioLoudnessProbing {
        private let inner: FakeAudioProbe
        private var release: CheckedContinuation<Void, Never>?
        /// Whether the surrounding task had been cancelled by the time the gate opened — the only
        /// place cancellation is visible, since the model drops its task handle regardless.
        private(set) var sawCancellation: Bool?
        init(_ inner: FakeAudioProbe) { self.inner = inner }
        func loudness(url: URL, from startSeconds: Double, seconds: Double) async -> LoudnessWindow? {
            await withCheckedContinuation { release = $0 }
            sawCancellation = Task.isCancelled
            return await inner.loudness(url: url, from: startSeconds, seconds: seconds)
        }
        func cancel() { inner.cancel(); finish() }
        func finish() { release?.resume(); release = nil }
    }

    /// The same shape of fixture the auto-sync suite uses: 60 irregular cues, dense enough for the
    /// correlation to find a sharp peak in a 90s window. Irregular because a metronome fixture
    /// scores the same at every whole-line shift and would pass against code measuring nothing.
    private static var syncCueTimes: [Double] {
        var seed: UInt64 = 424242
        var t = 5.0
        return (0..<60).map { _ in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            t += Double(3 + Int(seed >> 48) % 5)
            return t
        }
    }

    private static var syncSRT: String {
        syncCueTimes.enumerated().map { i, start in
            "\(i + 1)\n\(syncStamp(start)) --> \(syncStamp(start + 3))\nLine \(i)\n\n"
        }.joined()
    }

    private static func syncStamp(_ s: Double) -> String {
        String(format: "%02d:%02d:%02d,000", Int(s) / 3600, (Int(s) % 3600) / 60, Int(s) % 60)
    }
}
