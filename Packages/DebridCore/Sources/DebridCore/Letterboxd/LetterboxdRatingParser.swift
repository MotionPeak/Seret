import Foundation

/// Lifts Letterboxd's community average out of a film page's `ld+json` block.
///
/// The whole page is the only way in: the small `/csi/film/<slug>/rating-histogram/` fragment that
/// would otherwise carry this number answers 403 to every non-browser client, measured. So one
/// score costs ~47 KB gzipped, which is why the layer above caches every answer — including the
/// absence of one.
///
/// `NSRegularExpression` for the same reasons as `LetterboxdProfileParser`: no third-party
/// dependency, and a `Regex` is not `Sendable` so it cannot live in a `static let`.
public enum LetterboxdRatingParser {
    /// Letterboxd's own scale, straight off the page (`bestRating` 5, `worstRating` 0.5). A value
    /// outside it means the shape changed under us, and a nonsense figure in a chip labelled out
    /// of five reads worse than no chip at all.
    static let scale = 0.5...5.0

    private struct Document: Decodable {
        let aggregateRating: Aggregate?

        struct Aggregate: Decodable {
            let ratingValue: Double
            let ratingCount: Int
        }
    }

    private static let ldJSONRegex = make(#"<script[^>]*application/ld\+json[^>]*>(.*?)</script>"#,
                                          dotAll: true)

    public static func rating(fromFilmPage html: String) -> LetterboxdFilmRating? {
        for block in captures(html, ldJSONRegex) {
            guard let json = jsonObject(in: block),
                  let document = try? JSONDecoder().decode(Document.self, from: Data(json.utf8)),
                  let aggregate = document.aggregateRating else { continue }

            guard scale.contains(aggregate.ratingValue) else { return nil }
            return LetterboxdFilmRating(score: aggregate.ratingValue, count: aggregate.ratingCount)
        }
        return nil
    }

    /// Letterboxd wraps the block in `/* <![CDATA[ */ … /* ]]> */`, which is not JSON. Taking the
    /// span between the outermost braces strips the wrapper without depending on its exact text,
    /// so the parser keeps working if Letterboxd ever drops it.
    private static func jsonObject(in block: String) -> String? {
        guard let first = block.firstIndex(of: "{"), let last = block.lastIndex(of: "}"),
              first < last else { return nil }
        return String(block[first...last])
    }

    // MARK: - Regex plumbing

    private static func make(_ pattern: String, dotAll: Bool = false) -> NSRegularExpression {
        // The pattern is a literal in this file, so a failure is a programmer error, not input.
        try! NSRegularExpression(pattern: pattern,
                                 options: dotAll ? [.dotMatchesLineSeparators] : [])
    }

    private static func captures(_ s: String, _ re: NSRegularExpression) -> [String] {
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return re.matches(in: s, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: s) else { return nil }
            return String(s[r])
        }
    }
}
