import Foundation
import DebridCore

extension PlayerModel {

    // MARK: - Automatic subtitle sync
    //
    // ⚠️ BUILT, MEASURED, AND NOT OFFERED. The machinery works end to end — PCM out of libvlc, a
    // confirmed window, cue parsing, correlation, gates. What does not work is the FEATURE, and the
    // reason is the signal, not the plumbing.
    //
    // Measured on a real Apple TV library (Anna 2019, a Hebrew subtitle screenshot-verified as
    // correctly aligned — its "מוסקבה, 1985" sits exactly on the film's own "MOSCOW, 1985" card,
    // so the right answer is a shift of zero):
    //
    //     window 1428s (asked 1428s) · heard 219s of audio
    //     matched  → +83.4s  peak 0.269  OK
    //     envelope → +86.3s  peak 0.289  OK
    //     score at no-shift  -0.133
    //
    // At the CORRECT alignment the correlation is negative, and a wrong one scores +0.29. Loudness
    // is not a proxy for speech on this material — it is close to an inverted one. In an action
    // film the loud passages are gunfire and score, which carry no subtitles, while the dialogue is
    // quiet. So the measurement does not merely fail to find the answer; it confidently finds the
    // opposite, and would have dragged a correct subtitle eighty-six seconds out of true.
    //
    // What is missing is a voice-activity measure rather than a volume one — speech-band energy, a
    // voicing/spectral-flatness feature, or a real VAD. Until there is one, no entry point calls
    // `autoSyncSubtitle`, and the gates below are the only thing standing between this and a
    // wrecked subtitle.

    /// How much of the film to listen to. Long enough to cover a good number of lines — the peak
    /// gets sharper with every one — and short enough that it is a few minutes of the file rather
    /// than a second copy of it. Audio is interleaved with video in the container, so this really
    /// is minutes of download.
    /// The least audio worth correlating. Fewer lines than this and the peak is not a peak —
    /// measured on a real stream, a minute of a talkative film is about six cues.
    static let autoSyncMinimumSeconds: Double = 60
    /// A measurement below this is a guess. `SubtitleSync` already refuses the unconvincing; this
    /// is the second gate, because dragging a correct subtitle into nonsense is the one outcome
    /// worse than doing nothing.
    static let autoSyncMinimumConfidence = 0.35

    public enum AutoSyncState: Equatable, Sendable {
        case idle
        case measuring
        case synced
        /// Measured, and the answer was not worth acting on.
        case failed
    }

    /// Whether there is anything to sync.
    ///
    /// Only a DOWNLOADED subtitle qualifies, and that is not a shortcoming: a track muxed into the
    /// file was timed against that file by construction. Being out of step is something a subtitle
    /// fetched from somewhere else is, and for those we hold the actual cue times.
    public var canAutoSyncSubtitle: Bool { selectedDownloadedSubtitleFile != nil }

    /// The file backing the selected subtitle, if the selection is one we downloaded.
    var selectedDownloadedSubtitleFile: URL? {
        guard let selectedSubtitleID else { return nil }
        return attachedSubtitleTracks.first { $0.value == selectedSubtitleID }?.key
    }

    /// Listen to a few minutes of the film, line the subtitle's cues up against what was said, and
    /// dial in the difference.
    ///
    /// The offset is applied as a DELAY rather than by rewriting the file: it is instant, it is
    /// undoable with the existing Reset, and it composes with a rate correction the retimer may
    /// already have applied on the way in.
    public func autoSyncSubtitle() async {
        guard autoSyncState != .measuring,
              let audioProbe,
              let subtitleURL = selectedDownloadedSubtitleFile,
              let text = Self.readSubtitle(at: subtitleURL) else { return }

        autoSyncState = .measuring
        note("auto-sync: measuring \(Int(autoSyncWindow))s from \(Int(autoSyncWindowStart))s")
        defer { if autoSyncState == .measuring { autoSyncState = .failed } }

        guard let url = try? await unrestrict(currentSource.restrictedLink) else {
            note("auto-sync: could not open the media")
            return
        }
        let asked = autoSyncWindowStart
        guard let window = await audioProbe.loudness(url: url, from: asked,
                                                     seconds: autoSyncWindow),
              !window.frames.isEmpty else { note("auto-sync: no audio decoded"); return }
        // Where it ACTUALLY read from, which a seek decides and we do not.
        let start = window.startSeconds
        let loudness = window.frames
        note(String(format: "auto-sync: window %.0fs (asked %.0fs)", start, asked))
        // What came back is however much the connection managed, not the window we asked for.
        let measured = Double(loudness.count) * SubtitleSync.frameSeconds
        note(String(format: "auto-sync: heard %.0fs of audio", measured))
        guard measured >= Self.autoSyncMinimumSeconds else {
            note("auto-sync: too little audio to measure")
            return
        }

        // Two readings of the same audio: the thresholded one (a frame is speech or it is not) and
        // the raw envelope (louder means more likely to be talking). Which wins is a question about
        // real mixes, not one to settle from an armchair, so both are measured and the better peak
        // is taken. A film scored wall to wall has no quiet floor for a threshold to find, and the
        // envelope still carries the shape; a dialogue-over-silence mix is the other way round.
        let cues = SubtitleTiming.activity(in: text, frameSeconds: SubtitleSync.frameSeconds,
                                           frames: loudness.count, startSeconds: start)
        let speech = SpeechActivity.fromLoudness(loudness)
        note("auto-sync: \(speech.filter { $0 > 0 }.count) speech frames, "
             + "\(cues.filter { $0 > 0 }.count) cue frames")
        // …and a third, which is the one that should win: the loudest frames, in the same
        // proportion the SUBTITLE says are dialogue. The audio does not know how talkative this
        // stretch is; the cue list does, and matching the two densities is what makes the
        // correlation mean anything.
        let cueDensity = Double(cues.filter { $0 > 0 }.count) / Double(max(cues.count, 1))
        let matched = SpeechActivity.densest(loudness, fraction: cueDensity)

        let readings = [("matched", matched), ("threshold", speech),
                        ("envelope", loudness)].compactMap { name, signal in
            SubtitleSync.measure(speech: signal, cues: cues,
                                 frameSeconds: SubtitleSync.frameSeconds,
                                 maxLagSeconds: autoSyncMaxLag)
                .map { (name, $0) }
        }
        for (name, m) in readings { note("auto-sync: \(name) → \(m.summary)") }
        // What the CORRECT answer would have scored, when there is reason to think it is zero.
        // Without this a rejection cannot be told from a signal carrying no information at all.
        let atZero = SubtitleSync.correlation(speech: matched, cues: cues, lag: 0)
        note(String(format: "auto-sync: score at no-shift %.3f", atZero))

        guard let best = readings.filter({ $0.1.accepted }).max(by: { $0.1.peak < $1.1.peak })?.1,
              best.confidence >= Self.autoSyncMinimumConfidence else {
            note("auto-sync: no convincing match — leaving the subtitle alone")
            return
        }

        note(String(format: "auto-sync: applying %+.1fs (confidence %.2f)",
                    best.offsetSeconds, best.confidence))
        applySubtitleDelay(best.offsetSeconds)
        autoSyncState = .synced
    }

    /// Where in the film to listen.
    ///
    /// Not the opening: a release's first minutes are idents, black and a theme, which is both the
    /// least dialogue in the film and the part most likely to differ between releases — exactly
    /// the stretch that makes a subtitle wrong in the first place. A fifth of the way in is
    /// ordinary talking. Short media fall back to the start rather than past the end.
    var autoSyncWindowStart: Double {
        #if DEBUG
        // `-autoSyncFrom <seconds>` pins the window, so the cost of seeking into a stream can be
        // measured against reading it from the start with everything else held still.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-autoSyncFrom"), i + 1 < args.count,
           let pinned = Double(args[i + 1]) { return pinned }
        #endif
        guard duration > autoSyncWindow * 2 else { return 0 }
        return min(duration * 0.2, duration - autoSyncWindow)
    }

    /// Read a subtitle file as text, tolerating the encodings these files actually use.
    ///
    /// The same order `prepareSubtitle` uses, and for the same reason: a Hebrew file is often
    /// windows-1255, which is not valid UTF-8, and `isoLatin1` decodes any byte without failing.
    /// Only the timestamps are read here and those are ASCII either way.
    static func readSubtitle(at url: URL) -> String? {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        return try? String(contentsOf: url, encoding: .isoLatin1)
    }
}
