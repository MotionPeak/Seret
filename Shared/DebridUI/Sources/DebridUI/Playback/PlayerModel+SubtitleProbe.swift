#if DEBUG
import Foundation

/// DEBUG-only: log everything the APP does to the subtitle output, with the playhead beside it.
///
/// The open report is a cue that renders correctly and is then erased 0.1–0.2s later, in bursts of
/// a few seconds with healthy 1.0–1.5s cues either side. Captured on video and measured: real, and
/// not a timing error — the text is right, it is just taken away.
///
/// A cue on screen is removed when its end time passes, when a new cue replaces it, or when the SPU
/// is FLUSHED. Selecting a subtitle track flushes it. So the question this answers is simply:
/// **is the app re-selecting tracks during steady playback?** If it is, that is the bug and it is
/// ours. If the log is silent through a burst, the flush is inside libvlc — pair it with `-vlcLog`
/// and the answer is in libvlc's own SPU messages instead.
///
///     xcrun simctl launch <udid> com.solomons.seret.tv -autoPlay -subtitleProbe
///     xcrun devicectl device process launch --device <id> --console \
///         com.solomons.seret.tv -vlcLog -autoPlay -subtitleProbe
extension PlayerModel {

    static var subtitleProbeEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-subtitleProbe")
    }

    /// Stamp one subtitle event against the playhead. `@autoclosure` so a disabled probe costs
    /// nothing on a path that runs on every `.tracksChanged`.
    func subtitleProbe(_ event: @autoclosure () -> String) {
        guard Self.subtitleProbeEnabled else { return }
        // stderr, NOT print(). Swift's stdout is FULLY buffered when it is a pipe — which is what
        // `simctl launch --console` gives it — so a `print` probe emits nothing until the buffer
        // fills or the process exits, and a diagnostic you have to kill the app to read is no
        // diagnostic at all. libvlc's own lines show up precisely because it writes to stderr.
        FileHandle.standardError.write(
            Data((String(format: "[subs] %7.2fs %@", position, event()) + "\n").utf8))
    }

    /// How often `.tracksChanged` FIRES, reported every 10s of playback.
    ///
    /// The set-change log below is blind to a storm of events that all report the same set — and
    /// that storm is what would drive `refreshTracks()`, and with it the preference re-decisions,
    /// hundreds of times a second. A burst of flashes with a quiet set log but a screaming rate
    /// here would be the app thrashing; both quiet means the flush is inside libvlc.
    func probeTracksChangedRate() {
        guard Self.subtitleProbeEnabled else { return }
        tracksChangedCount += 1
        let now = Date().timeIntervalSince1970
        if tracksChangedWindowStart == 0 { tracksChangedWindowStart = now; return }
        guard now - tracksChangedWindowStart >= 10 else { return }
        subtitleProbe(String(format: "tracksChanged rate %.1f/s over %.0fs",
                             Double(tracksChangedCount) / (now - tracksChangedWindowStart),
                             now - tracksChangedWindowStart))
        tracksChangedCount = 0
        tracksChangedWindowStart = now
    }

    /// The subtitle track set as the engine currently reports it — the thing whose churn would
    /// drive a re-selection. Logged only when it CHANGES, so a burst stands out.
    func probeTrackSetIfChanged() {
        guard Self.subtitleProbeEnabled else { return }
        // Codec matters as much as the id: a BITMAP track (PGS/VobSub) is decoded image-by-image
        // and behaves nothing like text under load, so "which kind is on screen" is half the
        // question when cues are being dropped.
        let ids = engine.subtitleTracks
            .map { "\($0.id)|\($0.codec ?? "?")|\($0.language ?? "-")" }
            .joined(separator: " ")
        guard ids != lastProbedTrackSet else { return }
        lastProbedTrackSet = ids
        subtitleProbe("tracks -> [\(ids)]  selected=\(selectedSubtitleID ?? "nil")")
    }
}
#endif
