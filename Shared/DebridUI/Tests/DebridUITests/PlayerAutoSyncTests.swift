import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// Auto-sync end to end through `PlayerModel`: measure the audio, line the downloaded subtitle's
/// cues up against it, and dial in the offset it finds.
///
/// Only a DOWNLOADED subtitle can be synced this way, and that is not a limitation: a track muxed
/// into the file is timed against that file by construction. Being out of step is something a
/// subtitle fetched from somewhere else is.
@MainActor
// Serialised: each of these drives a full measurement and writes a subtitle file, and run in
// parallel they crowded out the sleep-based scan and progress suites sharing the machine — tests
// that were already the most fragile in the package.
@Suite(.serialized) struct PlayerAutoSyncTests {

    /// Where the subtitle CLAIMS each line is.
    ///
    /// Deliberately IRREGULAR. A line exactly every 15 seconds makes the correlation periodic —
    /// every shift of one whole line scores the same — so a metronome fixture tests the tie-break
    /// rather than the measurement, and would pass just as well against code that measured nothing.
    /// Real dialogue is uneven, and that unevenness is what makes the peak unique.
    /// WHOLE seconds, because `stamp` writes whole seconds. A fractional cue time is truncated on
    /// its way into the SRT while the fake probe keeps the exact value, which made the subtitle
    /// half a second early by construction — and the measurement dutifully reported that bias in
    /// every case, including the one that was supposed to need no correction at all.
    private var cueTimes: [Double] {
        var seed: UInt64 = 424242
        var t = 5.0
        // Only enough to cover the window the tests use, and densely — a big sparse fixture is
        // both more regex work and more correlation, and this suite starved the sleep-based scan
        // suites sharing the machine until it was cut down. Dense cues also keep the peak sharp in
        // a short window, which is what preserves the precision the assertions check.
        return (0..<60).map { _ in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            t += Double(3 + Int(seed >> 48) % 5)           // a line every 3–7 whole seconds
            return t
        }
    }

    /// The subtitle file for those cues.
    private var srt: String {
        cueTimes.enumerated().map { i, start in
            "\(i + 1)\n\(stamp(start)) --> \(stamp(start + 3))\nLine \(i)\n\n"
        }.joined()
    }

    private func stamp(_ s: Double) -> String {
        String(format: "%02d:%02d:%02d,000", Int(s) / 3600, (Int(s) % 3600) / 60, Int(s) % 60)
    }

    /// A model whose subtitle says the lines are at `cueTimes` while the audio has them
    /// `shiftSeconds` earlier — i.e. the subtitle runs that far LATE.
    private func model(shiftSeconds: Double, probe: FakeAudioProbe? = nil)
    -> (PlayerModel, FakeVideoPlayerEngine, FakeAudioProbe) {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        subs.downloadedText = srt
        let audio = probe ?? FakeAudioProbe.speaking(at: cueTimes.map { $0 - shiftSeconds })
        let m = PlayerModel(request: Fixture.request(), engine: engine,
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _ in }, subtitles: subs, audioProbe: audio,
                            autoSyncWindow: 90, autoSyncMaxLag: 5, autoSyncMinimumHalf: 25)
        return (m, engine, audio)
    }

    private func prepared(_ m: PlayerModel) async {
        m.start()
        await m.waitForIdleForTesting()
        await m.requestSubtitle(language: "he")
        await m.waitForIdleForTesting()
        m.setDurationForTesting(900)           // a 90s window with 45s halves
    }

    /// A subtitle running 4s LATE is corrected to show every line 4s earlier.
    @Test func aLateSubtitleIsPulledBackIntoLine() async {
        let (m, engine, probe) = model(shiftSeconds: 4)
        await prepared(m)

        await m.autoSyncSubtitle()

        #expect(m.autoSyncState == .synced)
        #expect(abs(m.subtitleDelay - (-4.0)) < 0.35)
        #expect(engine.subtitleDelays.last.map { abs($0 - (-4.0)) < 0.35 } == true)
        // It listened inside the film, not over the opening titles.
        #expect(probe.requests.first.map { $0.from > 60 } == true)
    }

    /// …and one running early is pushed later.
    @Test func anEarlySubtitleIsPushedLater() async {
        let (m, _, _) = model(shiftSeconds: -3)
        await prepared(m)

        await m.autoSyncSubtitle()

        #expect(m.autoSyncState == .synced)
        #expect(abs(m.subtitleDelay - 3.0) < 0.35)
    }

    /// An already-aligned subtitle is left where it is.
    @Test func anAlignedSubtitleIsNotNudged() async {
        let (m, _, _) = model(shiftSeconds: 0)
        await prepared(m)

        await m.autoSyncSubtitle()

        #expect(abs(m.subtitleDelay) < 0.35)
    }

    /// Audio it could not read is a measurement that did not happen. Leaving a correct subtitle
    /// alone is the only safe answer.
    @Test func audioThatCannotBeReadChangesNothing() async {
        let (m, _, _) = model(shiftSeconds: 4, probe: .silent)
        await prepared(m)

        await m.autoSyncSubtitle()

        #expect(m.autoSyncState == .failed)
        #expect(m.subtitleDelay == 0)
    }

    /// Noise must be refused rather than acted on — dragging a correct subtitle into nonsense is
    /// the one outcome worse than doing nothing.
    @Test func anUnmatchableSignalIsRefused() async {
        var seed: UInt64 = 99
        let noise = FakeAudioProbe(loudnessOnly: { _, seconds in
            (0..<Int(seconds / 0.1)).map { _ in
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Float(seed >> 40) / Float(1 << 24)
            }
        })
        let (m, _, _) = model(shiftSeconds: 4, probe: noise)
        await prepared(m)

        await m.autoSyncSubtitle()

        #expect(m.autoSyncState == .failed)
        #expect(m.subtitleDelay == 0)
    }

    /// With no downloaded subtitle there is nothing whose cue times we hold, so nothing to
    /// correlate — and a muxed track is in sync with its own file anyway.
    @Test func aMuxedTrackIsNotOfferedASync() async {
        let engine = FakeVideoPlayerEngine()
        engine.subtitleTracks = [MediaTrack(id: "spu/1", kind: .subtitle, name: "English",
                                            language: "en", codec: "subt")]
        let m = PlayerModel(request: Fixture.request(), engine: engine,
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _ in },
                            subtitles: FakeSubtitleProvider(), audioProbe: FakeAudioProbe.silent)
        m.start()
        engine.emit(.tracksChanged)
        await m.waitForIdleForTesting()
        m.selectSubtitle(id: "spu/1")

        #expect(m.canAutoSyncSubtitle == false)

        await m.autoSyncSubtitle()
        #expect(m.autoSyncState == PlayerModel.AutoSyncState.idle)   // never ran
        #expect(m.subtitleDelay == 0)
    }

    /// The case that defeated a loudness envelope on a real film: the LOUDEST moments are the ones
    /// with no subtitle — gunfire and score between the lines — while the dialogue is quiet. Volume
    /// correlates negatively here; voice does not.
    @Test func loudEffectsBetweenTheLinesDoNotFoolIt() async {
        let (m, _, _) = model(shiftSeconds: 4,
                              probe: .speaking(at: cueTimes.map { $0 - 4 }, effectsBetween: true))
        await prepared(m)

        await m.autoSyncSubtitle()

        #expect(m.autoSyncState == .synced)
        #expect(abs(m.subtitleDelay - (-4.0)) < 0.35)
    }

    /// The action becomes available exactly when a downloaded subtitle is on screen.
    @Test func aDownloadedSubtitleCanBeSynced() async {
        let (m, _, _) = model(shiftSeconds: 2)
        m.start()
        await m.waitForIdleForTesting()
        #expect(m.canAutoSyncSubtitle == false)      // nothing downloaded yet

        await m.requestSubtitle(language: "he")
        await m.waitForIdleForTesting()

        #expect(m.canAutoSyncSubtitle)
    }

    /// Without a probe wired in there is no feature, and asking for it must be a no-op rather than
    /// a spinner nothing clears.
    @Test func noProbeMeansNoOffer() async {
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        subs.downloadedText = srt
        let m = PlayerModel(request: Fixture.request(), engine: FakeVideoPlayerEngine(),
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _ in }, subtitles: subs)
        m.start()
        await m.waitForIdleForTesting()
        await m.requestSubtitle(language: "he")
        await m.waitForIdleForTesting()

        await m.autoSyncSubtitle()

        #expect(m.autoSyncState == PlayerModel.AutoSyncState.idle)
    }
}
