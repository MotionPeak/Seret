import Foundation

/// Parses cue timing out of an SRT or WebVTT subtitle file. Used to find when the dialogue
/// actually ends (the last cue) so the player can surface "Up Next" at content-end rather than at
/// the raw file end — TV rips often carry minutes of credits/black after the episode proper.
public enum SubtitleTiming {
    /// The end time (in seconds) of the last cue in an SRT/VTT string, or nil if none parse.
    /// Cue lines look like `00:01:02,500 --> 00:01:05,000` (SRT, comma) or
    /// `00:01:02.500 --> 00:01:05.000` (VTT, dot); we take the max end time across all cues
    /// (cues aren't guaranteed strictly ordered).
    public static func lastCueEndSeconds(in text: String) -> Double? {
        var maxEnd: Double?
        let range = NSRange(text.startIndex..., in: text)
        for m in cueRegex.matches(in: text, range: range) {
            guard let r = Range(m.range(at: 1), in: text), let secs = parseTimestamp(String(text[r]))
            else { continue }
            maxEnd = Swift.max(maxEnd ?? 0, secs)
        }
        return maxEnd
    }

    /// Every cue's start and end, in seconds, in the order they appear.
    ///
    /// `lastCueEndSeconds` only ever needed the ends. Syncing needs both: the shape being matched
    /// against the audio is "a line is on screen from here to here", and a cue's start is what
    /// carries that.
    public static func cueSpans(in text: String) -> [(start: Double, end: Double)] {
        let range = NSRange(text.startIndex..., in: text)
        return spanRegex.matches(in: text, range: range).compactMap { m in
            guard let s = Range(m.range(at: 1), in: text), let start = parseTimestamp(String(text[s])),
                  let e = Range(m.range(at: 2), in: text), let end = parseTimestamp(String(text[e])),
                  end > start else { return nil }
            return (start, end)
        }
    }

    /// The cues as one frame per `frameSeconds`: 1 while a line is on screen, 0 otherwise — the
    /// same shape `SpeechActivity` produces from the audio, so the two can be correlated.
    /// `startSeconds` is where the window begins in the media, because the audio it is matched
    /// against is a window too — measuring minute 20 of the film against minute 0 of the subtitle
    /// would "find" an offset of twenty minutes.
    public static func activity(in text: String, frameSeconds: Double, frames: Int,
                                startSeconds: Double = 0) -> [Float] {
        guard frameSeconds > 0, frames > 0 else { return [] }
        var v = [Float](repeating: 0, count: frames)
        for span in cueSpans(in: text) {
            let first = Int((span.start - startSeconds) / frameSeconds)
            let last = Int((span.end - startSeconds) / frameSeconds)
            guard first < frames, last >= 0 else { continue }   // outside the window entirely
            for i in max(0, first)...min(last, frames - 1) { v[i] = 1 }
        }
        return v
    }

    // Capture the END timestamp (group 1) of each "start --> end" cue line.
    private static let cueRegex = try! NSRegularExpression(
        pattern: #"\d{2}:\d{2}:\d{2}[,.]\d{1,3}\s*-->\s*(\d{2}:\d{2}:\d{2}[,.]\d{1,3})"#)
    // …and both sides of it, for `cueSpans`.
    private static let spanRegex = try! NSRegularExpression(
        pattern: #"(\d{2}:\d{2}:\d{2}[,.]\d{1,3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,.]\d{1,3})"#)

    /// `HH:MM:SS,mmm` or `HH:MM:SS.mmm` → seconds.
    private static func parseTimestamp(_ s: String) -> Double? {
        let parts = s.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]),
              let sec = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + sec
    }
}
