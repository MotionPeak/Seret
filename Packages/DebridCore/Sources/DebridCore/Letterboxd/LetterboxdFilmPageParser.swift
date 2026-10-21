import Foundation

/// What a single Letterboxd film page says about a film's makers and kind: its directors and its
/// genres. Feeds the "similar to what you watched" picks.
///
/// The whole page is the only way in, as with `LetterboxdRatingParser`, which reads the same
/// `ld+json` block this one takes the genres from.
public enum LetterboxdFilmPageParser {
    private struct Document: Decodable {
        let genre: [String]?
    }

    private static let directorRegex = make(#"href="/director/([^/"]+)/""#)
    private static let ldJSONRegex = make(#"<script[^>]*application/ld\+json[^>]*>(.*?)</script>"#,
                                          dotAll: true)

    /// Director slugs from the credit line's `/director/<slug>/` links, unique, in page order.
    /// Only the bare link counts: `/director/<slug>/decade/…` and friends are filters, not credits.
    public static func directorSlugs(fromFilmPage html: String) -> [String] {
        var seen = Set<String>()
        return captures(html, directorRegex).filter { seen.insert($0).inserted }
    }

    /// The `genre` array of the page's `ld+json` block, in the order Letterboxd lists it.
    public static func genres(fromFilmPage html: String) -> [String] {
        for block in captures(html, ldJSONRegex) {
            guard let json = jsonObject(in: block),
                  let document = try? JSONDecoder().decode(Document.self, from: Data(json.utf8)),
                  let genres = document.genre else { continue }
            return genres.map { HTMLEntities.decode($0) }
        }
        return []
    }

    /// Letterboxd wraps the block in `/* <![CDATA[ */ … /* ]]> */`, which is not JSON. Taking the
    /// span between the outermost braces strips the wrapper without depending on its exact text.
    private static func jsonObject(in block: String) -> String? {
        guard let first = block.firstIndex(of: "{"), let last = block.lastIndex(of: "}"),
              first < last else { return nil }
        return String(block[first...last])
    }

    // MARK: - Regex plumbing

    private static func make(_ pattern: String, dotAll: Bool = false) -> NSRegularExpression {
        // The patterns are literals in this file, so a failure is a programmer error, not input.
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
