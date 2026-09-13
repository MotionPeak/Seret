import Foundation

/// One subtitle line, with the times it was authored against.
public struct SubtitleCue: Sendable, Equatable, Identifiable {
    /// Ordinal in the parsed, time-sorted list. Deliberately NOT the file's own cue number: that
    /// numbering is frequently wrong, duplicated, or absent, and the panel indexes by position.
    public let id: Int
    public let start: Double
    public let end: Double
    /// The cue's lines joined by a space, with markup removed.
    public let text: String

    public init(id: Int, start: Double, end: Double, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Parses an SRT or WebVTT file into its lines.
///
/// `SubtitleTiming` answers "when does the dialogue end" and "when is a line on screen"; this
/// answers "what are the lines". A viewer syncing by hand has to see the line they are pressing
/// against, which means the text has to survive parsing.
public enum SubtitleCues {

    /// Every cue in the file, sorted by start time and numbered in that order.
    ///
    /// Scans line by line rather than splitting on blank lines, because real files are not reliably
    /// blank-line separated and the old regex-over-the-whole-text approach found their cues anyway.
    /// Losing that tolerance would quietly degrade auto-sync, which parses the same files.
    public static func parse(_ text: String) -> [SubtitleCue] {
        var raw: [(start: Double, end: Double, lines: [String])] = []
        for line in normalizedLines(text) {
            if let span = timing(line) {
                // A cue's own number sits on the line BEFORE its timing line, so it has already
                // been buffered as if it were the previous cue's dialogue. Now that the next timing
                // line has arrived, a trailing all-digits line is known to be that number.
                if var previous = raw.popLast() {
                    if let tail = previous.lines.last, Int(tail) != nil { previous.lines.removeLast() }
                    raw.append(previous)
                }
                raw.append((span.start, span.end, []))
            } else if !raw.isEmpty, !line.isEmpty {
                raw[raw.count - 1].lines.append(line)
            }
            // Anything before the first timing line — an SRT's leading index, a VTT's `WEBVTT`
            // header and its metadata — falls through both branches and is dropped.
        }
        return raw
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
            .enumerated()
            .map { SubtitleCue(id: $0.offset, start: $0.element.start, end: $0.element.end,
                               text: clean($0.element.lines.joined(separator: " "))) }
    }

    /// The index of the cue on screen at `seconds`, or failing that the one starting nearest to it.
    ///
    /// "On screen" first, because when the panel opens mid-line that line is the one the viewer is
    /// looking at — and pre-selecting it is what makes the common case a single press.
    public static func nearest(to seconds: Double, in cues: [SubtitleCue]) -> Int? {
        guard !cues.isEmpty else { return nil }
        if let onScreen = cues.firstIndex(where: { seconds >= $0.start && seconds <= $0.end }) {
            return onScreen
        }
        return cues.indices.min { abs(cues[$0].start - seconds) < abs(cues[$1].start - seconds) }
    }

    /// `index` with up to `radius` cues either side, clamped to the list. Empty when `index` is not
    /// a valid position, so a caller cannot render a selection that does not exist.
    public static func slice(around index: Int, radius: Int, in cues: [SubtitleCue]) -> [SubtitleCue] {
        guard cues.indices.contains(index) else { return [] }
        let lower = max(0, index - radius)
        let upper = min(cues.count - 1, index + radius)
        return Array(cues[lower...upper])
    }

    // MARK: - Parsing internals

    /// Line endings normalised, a BOM dropped, and each line trimmed — a "blank" line in the wild
    /// often carries spaces, and a trailing `\r` would otherwise ride along in the text.
    private static func normalizedLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// `HH:MM:SS,mmm --> HH:MM:SS,mmm` (SRT) or the same with dots (VTT), anywhere in the line —
    /// VTT appends cue settings like `line:90%` after the timestamps.
    private static func timing(_ line: String) -> (start: Double, end: Double)? {
        let range = NSRange(line.startIndex..., in: line)
        guard let m = timingRegex.firstMatch(in: line, range: range),
              let s = Range(m.range(at: 1), in: line), let start = timestamp(String(line[s])),
              let e = Range(m.range(at: 2), in: line), let end = timestamp(String(line[e]))
        else { return nil }
        return (start, end)
    }

    private static let timingRegex = try! NSRegularExpression(
        pattern: #"(\d{2}:\d{2}:\d{2}[,.]\d{1,3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,.]\d{1,3})"#)

    /// `<i>`/`</b>` markup and `{\an8}`-style ASS overrides, which are positioning instructions
    /// rather than dialogue and would otherwise be read as part of the line.
    private static let markupRegex = try! NSRegularExpression(pattern: #"<[^>]*>|\{[^}]*\}"#)

    private static func clean(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        let stripped = markupRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return stripped.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                       .trimmingCharacters(in: .whitespaces)
    }

    /// `HH:MM:SS,mmm` or `HH:MM:SS.mmm` → seconds.
    private static func timestamp(_ s: String) -> Double? {
        let parts = s.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]),
              let sec = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + sec
    }
}
