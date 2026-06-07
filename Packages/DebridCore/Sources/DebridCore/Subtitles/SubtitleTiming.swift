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

    // Capture the END timestamp (group 1) of each "start --> end" cue line.
    private static let cueRegex = try! NSRegularExpression(
        pattern: #"\d{2}:\d{2}:\d{2}[,.]\d{1,3}\s*-->\s*(\d{2}:\d{2}:\d{2}[,.]\d{1,3})"#)

    /// `HH:MM:SS,mmm` or `HH:MM:SS.mmm` → seconds.
    private static func parseTimestamp(_ s: String) -> Double? {
        let parts = s.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]),
              let sec = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + sec
    }
}
