import Foundation

/// Turns one page of a Letterboxd profile grid into entries.
///
/// `NSRegularExpression` rather than an HTML parser because `DebridCore` takes no third-party
/// dependencies, and rather than Swift's `Regex` because a `Regex` is not `Sendable` and so cannot
/// be cached in a `static let` under strict concurrency. Same choice `FilenameParser` made.
///
/// The contract is narrow on purpose: each film is one `li.griditem` carrying `data-item-slug` and
/// `data-item-name`, with an optional sibling `span.rating.rated-N`.
public enum LetterboxdProfileParser {
    public struct ParsedPage: Sendable, Equatable {
        public let entries: [LetterboxdEntry]
        public let nextPath: String?

        public init(entries: [LetterboxdEntry], nextPath: String?) {
            self.entries = entries
            self.nextPath = nextPath
        }
    }

    private static let itemRegex = make(#"<li class="griditem".*?</li>"#, dotAll: true)
    private static let slugRegex = make(#"data-item-slug="([^"]+)""#)
    private static let nameRegex = make(#"data-item-name="([^"]+)""#)
    /// `\b` stops this matching the tail of something like `unrated-`.
    private static let ratedRegex = make(#"\brated-(\d{1,2})\b"#)
    /// The LAST parenthesised year in the display name — "Am I OK? (2022)" has punctuation before it.
    private static let yearRegex = make(#"\((\d{4})\)[^(]*$"#)
    private static let nextRegex = make(#"<a class="next" href="([^"]+)""#)

    public static func parse(_ html: String) throws -> ParsedPage {
        var entries: [LetterboxdEntry] = []

        for block in wholeMatches(html, itemRegex) {
            guard let slug = firstCapture(block, slugRegex),
                  let name = firstCapture(block, nameRegex) else { continue }

            let rating = firstCapture(block, ratedRegex).flatMap { Int($0) }
            let year = firstCapture(name, yearRegex).flatMap { Int($0) }

            entries.append(LetterboxdEntry(slug: slug,
                                           name: name,
                                           year: year,
                                           rating: rating.flatMap { (1...10).contains($0) ? $0 : nil }))
        }

        guard !entries.isEmpty else { throw LetterboxdError.structureChanged }

        return ParsedPage(entries: entries, nextPath: firstCapture(html, nextRegex))
    }

    // MARK: - Regex plumbing

    private static func make(_ pattern: String, dotAll: Bool = false) -> NSRegularExpression {
        // The patterns are literals in this file, so a failure is a programmer error, not input.
        try! NSRegularExpression(pattern: pattern,
                                 options: dotAll ? [.dotMatchesLineSeparators] : [])
    }

    private static func firstCapture(_ s: String, _ re: NSRegularExpression) -> String? {
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let match = re.firstMatch(in: s, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: s) else { return nil }
        return String(s[captured])
    }

    private static func wholeMatches(_ s: String, _ re: NSRegularExpression) -> [String] {
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return re.matches(in: s, range: range).compactMap {
            Range($0.range, in: s).map { String(s[$0]) }
        }
    }
}
