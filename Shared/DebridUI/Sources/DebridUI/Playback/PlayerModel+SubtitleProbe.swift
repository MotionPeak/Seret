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

    // MARK: - Driving a pick without a remote

    /// `-autoSubtitle <lang>` — pick that language a few seconds into playback, exactly as the
    /// viewer does, and then report what the engine is left holding.
    ///
    /// Walking the focus engine to the settings panel costs minutes per attempt and lands on the
    /// wrong row half the time; the report is about what the app DOES with the pick, not about
    /// how the row was reached. `-autoSubtitleBrowser` takes the search-browser route instead of
    /// the one-tap pill, because those are two different code paths and only one of them declares
    /// the pick a viewer decision.
    ///
    ///     xcrun simctl launch <udid> com.solomons.seret.tv \
    ///         -autoPlay -subtitleProbe -autoSubtitle he
    static var autoSubtitleLanguage: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-autoSubtitle"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var autoSubtitleUsesBrowser: Bool {
        ProcessInfo.processInfo.arguments.contains("-autoSubtitleBrowser")
    }

    /// Fire once, after the stream has settled — a pick made while tracks are still being parsed
    /// measures the discovery race rather than the pick.
    func startSubtitleProbeIfRequested() {
        guard !subtitleProbeStarted, let language = Self.autoSubtitleLanguage else { return }
        subtitleProbeStarted = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self else { return }
            let route = Self.autoSubtitleUsesBrowser ? "browser" : "pill"
            self.subtitleProbe("PROBE picking \(language) via the \(route)")
            if Self.autoSubtitleUsesBrowser {
                await self.searchSubtitles(language: language)
                self.subtitleProbe("PROBE search → \(self.subtitleSearchResults.count) results")
                guard let best = self.subtitleSearchResults.first else { return }
                await self.useSubtitle(best)
            } else {
                await self.requestSubtitle(language: language)
            }
            // …and only THEN travel to a cue, so the screenshot that answers "does it render?"
            // is taken with the chosen track already on the output. Seeking first and attaching
            // afterwards leaves the two racing, and a blank frame then proves nothing.
            if let target = Self.autoSubtitleSeek {
                self.subtitleProbe("PROBE seeking to \(Int(target))s for a cue")
                self.engine.seek(to: target)
            }
            for _ in 0..<12 {
                try? await Task.sleep(for: .seconds(2))
                self.subtitleProbe("PROBE selected=\(self.selectedSubtitleID ?? "nil") "
                    + "picked=\(self.subtitlePickedByUser) rows=\(self.probeRows)")
            }
        }
    }

    /// `-autoSubtitleSeek <seconds>` — where to travel once the pick has landed.
    static var autoSubtitleSeek: Double? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-autoSubtitleSeek"), i + 1 < args.count else { return nil }
        return Double(args[i + 1])
    }

    private var probeRows: String {
        subtitleRows.map { "\($0.language):\($0.state)" }.joined(separator: ",")
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
