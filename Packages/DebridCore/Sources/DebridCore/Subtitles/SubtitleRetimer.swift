import Foundation

/// Rewrites a subtitle file's cue timings onto the frame rate of the video actually playing.
///
/// This is the fix for the drift that makes a title unwatchable partway through. A subtitle
/// carries absolute timestamps, so one authored against a different master runs at a different
/// RATE — not a fixed offset. The classic pair is a 25fps PAL broadcast master against a 23.976
/// encode: the PAL version is sped up ~4%, so its cues arrive progressively early until each line
/// is clipped by its successor and no sentence finishes on screen.
///
/// A constant subtitle delay cannot fix that — only rescaling can, and the arithmetic is exact:
/// a cue at time `t` in a `subtitleFPS` master sits at `t × subtitleFPS / videoFPS` in a
/// `videoFPS` one. Measured on the case that prompted this: every one of the 29 subtitles
/// OpenSubtitles carries for Sherlock S02E01 — English and Hebrew alike — is timed at 25fps, so
/// no amount of better ranking can find a good one. There is no correct candidate to choose;
/// the chosen one has to be corrected.
public enum SubtitleRetimer {

    /// Below this the correction is imperceptible (24 → 23.976 is a millisecond an hour) and not
    /// worth rewriting a file for.
    private static let minimumCorrection = 0.002
    /// Every real rate pair — 25/23.976, 25/24, 24/23.976, 30/29.97 — lands inside ±5%. A ratio
    /// outside it means the metadata is wrong, and acting on it would wreck a subtitle that may
    /// well have been fine.
    private static let plausible = 0.95...1.05
    /// Cues already reaching this far into the runtime belong to THIS cut, whatever rate the
    /// uploader declared. Believe the file over the metadata.
    private static let alreadySpansRuntime = 0.97
    /// Cues may end slightly past a runtime the engine has only estimated; well past it means the
    /// correction is wrong.
    private static let runtimeTolerance = 1.02

    /// The multiplier that moves `subtitleFPS`-timed cues onto a `videoFPS` timeline, or nil when
    /// no correction should be applied.
    ///
    /// `lastCueEnd` and `duration` are optional evidence from the file itself. They are the guard
    /// against a wrong declared rate: a correction that would push dialogue past the end of the
    /// video, or one applied to a subtitle whose cues already span the runtime, is refused.
    public static func factor(subtitleFPS: Double?, videoFPS: Double?,
                              lastCueEnd: Double? = nil, duration: Double? = nil) -> Double? {
        guard let subtitleFPS, subtitleFPS > 0,      // OpenSubtitles sends 0.0 for "unknown"
              let videoFPS, videoFPS > 0 else { return nil }
        let factor = subtitleFPS / videoFPS
        guard abs(factor - 1) > minimumCorrection, plausible.contains(factor) else { return nil }
        if let lastCueEnd, lastCueEnd > 0, let duration, duration > 0 {
            guard lastCueEnd / duration < alreadySpansRuntime,
                  lastCueEnd * factor <= duration * runtimeTolerance else { return nil }
        }
        return factor
    }

    /// Multiply every cue timestamp in an SRT or WebVTT string by `factor`, leaving cue indices,
    /// dialogue and WebVTT cue settings untouched.
    public static func rescale(_ text: String, by factor: Double) -> String {
        guard factor > 0, abs(factor - 1) > .ulpOfOne else { return text }
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for match in cueRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let start = ns.substring(with: match.range(at: 1))
            let arrow = ns.substring(with: match.range(at: 2))
            let end = ns.substring(with: match.range(at: 3))
            guard let from = seconds(start), let to = seconds(end) else { continue }
            out += ns.substring(with: NSRange(location: cursor,
                                             length: match.range.location - cursor))
            out += stamp(from * factor, separator: separator(in: start))
            out += arrow
            out += stamp(to * factor, separator: separator(in: end))
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    // Both timestamps of a cue line, with the arrow between them kept verbatim. Hours are optional
    // because WebVTT permits `MM:SS.mmm`; the millisecond separator is `,` in SRT and `.` in VTT.
    private static let cueRegex = try! NSRegularExpression(
        pattern: #"((?:\d+:)?\d{1,2}:\d{2}[,.]\d{1,3})(\s*-->\s*)((?:\d+:)?\d{1,2}:\d{2}[,.]\d{1,3})"#)

    private static func separator(in stamp: String) -> Character {
        stamp.contains(",") ? "," : "."
    }

    /// `HH:MM:SS,mmm`, `HH:MM:SS.mmm` or `MM:SS.mmm` → seconds.
    private static func seconds(_ stamp: String) -> Double? {
        let parts = stamp.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard let last = parts.last, let secs = Double(last) else { return nil }
        switch parts.count {
        case 3:
            guard let h = Double(parts[0]), let m = Double(parts[1]) else { return nil }
            return h * 3600 + m * 60 + secs
        case 2:
            guard let m = Double(parts[0]) else { return nil }
            return m * 60 + secs
        default:
            return nil
        }
    }

    /// Seconds → `HH:MM:SS,mmm`, always with hours. That full form is valid in both formats, so an
    /// hourless WebVTT stamp is simply normalised rather than needing a second code path.
    private static func stamp(_ total: Double, separator: Character) -> String {
        let ms = max(0, Int((total * 1000).rounded()))
        return String(format: "%02d:%02d:%02d%@%03d",
                      ms / 3_600_000, (ms % 3_600_000) / 60_000, (ms % 60_000) / 1000,
                      String(separator), ms % 1000)
    }
}
