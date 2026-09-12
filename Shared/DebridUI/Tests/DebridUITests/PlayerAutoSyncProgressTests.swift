import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// A sync takes minutes, because measuring the audio means downloading it. That is only tolerable
/// if the viewer can start it, close the panel, carry on watching, and see how it is going.
@MainActor
@Suite(.serialized) struct PlayerAutoSyncProgressTests {

    /// A probe that reports progress and finishes only when told to, so the in-flight state can be
    /// observed rather than raced.
    final class SlowProbe: AudioLoudnessProbing {
        private let window: LoudnessWindow
        private(set) var cancelled = false
        private(set) var asks = 0
        var measuredSeconds: Double = 0
        private var release: CheckedContinuation<Void, Never>?

        init(window: LoudnessWindow) { self.window = window }

        func loudness(url: URL, from startSeconds: Double, seconds: Double) async -> LoudnessWindow? {
            asks += 1
            await withCheckedContinuation { release = $0 }
            return cancelled ? nil : window
        }
        func cancel() { cancelled = true; finish() }
        /// Let the measurement complete.
        func finish() { release?.resume(); release = nil }
    }

    private func model(_ probe: AudioLoudnessProbing) -> PlayerModel {
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        subs.downloadedText = "1\n00:00:05,000 --> 00:00:08,000\nLine\n\n"
        let m = PlayerModel(request: Fixture.request(), engine: FakeVideoPlayerEngine(),
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _ in }, subtitles: subs, audioProbe: probe,
                            autoSyncWindow: 90, autoSyncMaxLag: 5, autoSyncMinimumHalf: 25)
        return m
    }

    private func ready(_ m: PlayerModel) async {
        m.start()
        await m.waitForIdleForTesting()
        await m.requestSubtitle(language: "he")
        await m.waitForIdleForTesting()
        m.setDurationForTesting(900)
    }

    /// Starting a sync returns immediately — the viewer is not held while minutes of audio are
    /// fetched — and the measurement carries on behind them.
    @Test func startingASyncDoesNotBlockTheViewer() async {
        let probe = SlowProbe(window: LoudnessWindow(frames: [], startSeconds: 0))
        let m = model(probe)
        await ready(m)

        m.startAutoSync()                       // no await: this must not be a waiting call
        await m.settleForTesting()

        #expect(m.autoSyncState == .measuring)
        #expect(m.autoSyncProgress != nil)

        probe.finish()
        await m.settleForTesting()
    }

    /// Progress is reported as a fraction of the window asked for, so the bar can move.
    @Test func progressTracksTheAudioGatheredSoFar() async {
        let probe = SlowProbe(window: LoudnessWindow(frames: [], startSeconds: 0))
        let m = model(probe)
        await ready(m)
        m.startAutoSync()
        await m.settleForTesting()

        probe.measuredSeconds = 45              // half of the 90s window
        await m.pollAutoSyncProgressForTesting()

        let fraction = m.autoSyncProgress?.fraction ?? 0
        #expect(abs(fraction - 0.5) < 0.05)

        probe.finish()
        await m.settleForTesting()
    }

    /// An estimate appears once there is enough to estimate from, and is absent before that rather
    /// than being invented.
    @Test func aRemainingTimeAppearsOnlyOnceItCanBeKnown() async {
        let probe = SlowProbe(window: LoudnessWindow(frames: [], startSeconds: 0))
        let m = model(probe)
        await ready(m)
        m.startAutoSync()
        await m.settleForTesting()

        #expect(m.autoSyncProgress?.secondsRemaining == nil)   // nothing gathered yet

        probe.measuredSeconds = 30
        await m.pollAutoSyncProgressForTesting(after: 10)
        probe.measuredSeconds = 60
        await m.pollAutoSyncProgressForTesting(after: 20)

        #expect(m.autoSyncProgress?.secondsRemaining != nil)

        probe.finish()
        await m.settleForTesting()
    }

    /// Leaving the player abandons the measurement — it must not outlive the thing it measures, or
    /// keep pulling a stream nobody is watching.
    @Test func leavingThePlayerAbandonsTheMeasurement() async {
        let probe = SlowProbe(window: LoudnessWindow(frames: [], startSeconds: 0))
        let m = model(probe)
        await ready(m)
        m.startAutoSync()
        await m.settleForTesting()

        await m.teardown()
        await m.settleForTesting()

        #expect(probe.cancelled)
        #expect(m.autoSyncProgress == nil)
    }

    /// Asking twice while one is running does not start a second measurement.
    @Test func aSecondRequestWhileMeasuringIsIgnored() async {
        let probe = SlowProbe(window: LoudnessWindow(frames: [], startSeconds: 0))
        let m = model(probe)
        await ready(m)
        m.startAutoSync()
        await m.settleForTesting()
        let first = m.autoSyncProgress

        m.startAutoSync()
        await m.settleForTesting()

        #expect(m.autoSyncState == .measuring)
        #expect(m.autoSyncProgress?.fraction == first?.fraction)
        #expect(probe.asks == 1, "a second Sync must not fetch the audio again")

        probe.finish()
        await m.settleForTesting()
    }

    /// When it ends, the progress goes away so the bar can show the outcome instead.
    @Test func progressClearsWhenTheMeasurementEnds() async {
        let probe = SlowProbe(window: LoudnessWindow(frames: [], startSeconds: 0))
        let m = model(probe)
        await ready(m)
        m.startAutoSync()
        await m.settleForTesting()

        probe.finish()
        await m.settleForTesting()

        #expect(m.autoSyncState == .failed)     // the window was empty — nothing to measure
        #expect(m.autoSyncProgress == nil)
    }

    /// The bar over the picture says what is happening and how far along it is, so the viewer can
    /// go back to the film without wondering whether anything is still running.
    @Test func theBarSaysWhatIsHappeningWhileItListens() async {
        let probe = SlowProbe(window: LoudnessWindow(frames: [], startSeconds: 0))
        let m = model(probe)
        await ready(m)

        #expect(m.autoSyncBanner == nil, "nothing to say before it starts")
        m.startAutoSync()
        await m.settleForTesting()

        #expect(m.autoSyncBanner?.text.contains("Syncing subtitles") == true)
        #expect(m.autoSyncBanner?.fraction != nil)

        probe.finish()
        await m.settleForTesting()
    }

    /// The bar reports the outcome — and then gets off the picture. A banner that never leaves is
    /// worse than no banner.
    @Test func theBarReportsTheOutcomeThenGoesAway() async {
        let probe = SlowProbe(window: LoudnessWindow(frames: [], startSeconds: 0))
        let m = model(probe)
        await ready(m)
        m.autoSyncOutcomeSeconds = 0.05
        m.startAutoSync()
        await m.settleForTesting()

        probe.finish()
        await m.settleForTesting()

        #expect(m.autoSyncBanner?.text.contains("Couldn't sync") == true)
        #expect(m.autoSyncBanner?.fraction == nil, "nothing left to fill")

        try? await Task.sleep(for: .seconds(0.2))
        #expect(m.autoSyncBanner == nil)
    }

    /// A sync the viewer walked out on reports nothing — the answer is about a film they left.
    @Test func abandoningItReportsNoOutcome() async {
        let probe = SlowProbe(window: LoudnessWindow(frames: [], startSeconds: 0))
        let m = model(probe)
        await ready(m)
        m.startAutoSync()
        await m.settleForTesting()

        await m.teardown()
        await m.settleForTesting()

        #expect(m.autoSyncBanner == nil)
        #expect(m.autoSyncOutcome == nil)
    }
}
