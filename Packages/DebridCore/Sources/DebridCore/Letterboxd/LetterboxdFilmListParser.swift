import Foundation

/// Reads the films out of any Letterboxd page that renders posters: a film's `/similar/` page and a
/// director's page, today.
///
/// The two pages wrap their posters differently — `/similar/` uses `li.griditem`, a director's page
/// uses `li.tooltip.griditem` — but both put `data-item-slug` and `data-item-name` on the poster's
/// own element. So this keys on those two attributes, wherever they sit, instead of on any one
/// layout; `LetterboxdProfileParser` is the strict, throwing reader for the profile grid.
///
/// `NSRegularExpression` for the same reasons as `LetterboxdProfileParser`: no third-party
/// dependency, and a `Regex` is not `Sendable` so it cannot live in a `static let`.
public enum LetterboxdFilmListParser {
    /// One opening tag. Quoted attribute values are consumed whole, so a `>` inside one (the
    /// poster-metadata JSON attributes are full of punctuation) cannot end the tag early. The
    /// alternatives start with disjoint characters, so matching is linear.
    private static let tagRegex = make(#"<[a-zA-Z][a-zA-Z0-9]*(?:[^>"']|"[^"]*"|'[^']*')*>"#)
    private static let slugRegex = make(#"\bdata-item-slug="([^"]+)""#)
    private static let nameRegex = make(#"\bdata-item-name="([^"]+)""#)
    /// The LAST parenthesised year in the display name — "Am I OK? (2022)" has punctuation before it.
    private static let yearRegex = make(#"\((\d{4})\)[^(]*$"#)

    /// Every film on the page in page order, once each. `[]` when there are none — a page that
    /// changed shape and a page with no films look the same here, and the caller decides what an
    /// empty answer means.
    public static func parse(_ html: String) -> [LetterboxdEntry] {
        guard html.contains("data-item-slug") else { return [] }

        var entries: [LetterboxdEntry] = []
        var seen = Set<String>()

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in tagRegex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            guard let slug = firstCapture(tag, slugRegex),
                  let escaped = firstCapture(tag, nameRegex),
                  seen.insert(slug).inserted else { continue }

            // Read out of an HTML attribute, so it arrives escaped (`Honey Don&#039;t!`).
            let name = HTMLEntities.decode(escaped)
            let year = firstCapture(name, yearRegex).flatMap { Int($0) }
            entries.append(LetterboxdEntry(slug: slug, name: name, year: year, rating: nil))
        }
        return entries
    }

    // MARK: - Regex plumbing

    private static func make(_ pattern: String) -> NSRegularExpression {
        // The patterns are literals in this file, so a failure is a programmer error, not input.
        try! NSRegularExpression(pattern: pattern)
    }

    private static func firstCapture(_ s: String, _ re: NSRegularExpression) -> String? {
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let match = re.firstMatch(in: s, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: s) else { return nil }
        return String(s[captured])
    }
}
