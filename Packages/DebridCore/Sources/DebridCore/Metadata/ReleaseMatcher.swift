import Foundation

/// Hard gate that decides whether a parsed release plausibly corresponds to a requested title.
///
/// Stream indexers (Comet and its upstream scrapers) attribute torrents to an IMDB id by
/// fuzzy-matching release *names*, so a brand-new or generically-titled film ("Obsession")
/// can come back with unrelated junk — an old same-named film, or porn — that shares the title
/// string. This matcher keeps that junk out of a title's version list.
///
/// Pure and dependency-free; the same gate is reused by the search→add flow (`CometStreamSource`)
/// and library enrichment (`MetadataEnricher`).
public struct ReleaseMatcher: Sendable {
    public init() {}

    /// A movie release matches when its title contains the requested title (after normalization)
    /// **and** survives the confidence gate:
    /// - If both carry a year, they must be within ±1 (an early cam can be tagged a year early).
    /// - If the release has *no* year, it must at least carry real quality metadata — a bare
    ///   `Obsession.avi` with neither year nor resolution is exactly the mis-attributed junk we drop.
    ///
    /// An empty requested title disables filtering (returns `true`) — there's nothing to match against.
    public func matchesMovie(_ parsed: ParsedRelease, title: String, year: Int?) -> Bool {
        // A movie is never a season pack / episode. Scrapers mis-attribute a same-named TV series
        // (e.g. "Obsession.S01…") to the movie's IMDB id; reject anything carrying season/episode.
        guard !parsed.isTV else { return false }
        let req = Self.normalize(title)
        guard !req.isEmpty else { return true }
        let rel = Self.normalize(parsed.title)

        if let want = year, let got = parsed.year {
            // A matching year (±1) is a strong signal, so a lenient substring title is fine here.
            return rel.contains(req) && abs(want - got) <= 1
        }
        if parsed.year == nil {
            // No year to lean on → demand a stronger title match (the release must LEAD with the
            // requested title, not merely contain it) plus real quality metadata. This rejects junk
            // like "BlackForWife … Sex Obsession XXX 2160p" where the title is buried mid-string.
            return rel.hasPrefix(req) && (parsed.resolution != nil || parsed.source != nil)
        }
        return rel.contains(req)   // release has a year, request didn't — title gate only
    }

    /// A series release matches on title alone. Per-episode years are unreliable (an episode is
    /// often tagged its air year, not the show's first-air year), so there is no year gate here.
    public func matchesSeries(_ parsed: ParsedRelease, title: String) -> Bool {
        let req = Self.normalize(title)
        guard !req.isEmpty else { return true }
        return Self.normalize(parsed.title).contains(req)
    }

    /// Symmetric title check for matching a parsed name to a metadata candidate (TMDB). True when
    /// either normalized title contains the other — lenient enough for article/punctuation drift,
    /// strict enough to reject an unrelated film. A blank title on either side can't be compared,
    /// so it passes (the caller falls back to other signals, e.g. TMDB's year-filtered search).
    public func titleMatches(_ a: String, _ b: String) -> Bool {
        let x = Self.normalize(a), y = Self.normalize(b)
        guard !x.isEmpty, !y.isEmpty else { return true }
        return x.contains(y) || y.contains(x)
    }

    /// A looser title check for a search that was already pinned to a release YEAR: every word of
    /// `candidate` appears in `parsed`, in order, and those words are most of `parsed`.
    ///
    /// Release names carry words a TMDB title drops. "Star Wars Episode VII The Force Awakens" is
    /// TMDB's "Star Wars: The Force Awakens"; "American Pie Reunion" is "American Reunion". The
    /// year-filtered search returns exactly that film, but neither normalized title contains the
    /// other, so `titleMatches` rejected it and both owned films stayed posterless.
    ///
    /// Strict on purpose: the words appear in order, cover at least 60% of the parsed words, and
    /// at least two of them carry meaning — "The King" is not "The Lion King" (2019) just because
    /// "the" matched. "American Wedding" (a word out of place) still fails.
    public func wordsAppearInOrder(_ candidate: String, in parsed: String) -> Bool {
        let want = Self.words(candidate), have = Self.words(parsed)
        guard want.filter({ !Self.stopWords.contains($0) }).count >= 2, !have.isEmpty,
              Double(want.count) / Double(have.count) >= 0.6 else { return false }
        var remaining = want[...]
        for word in have where word == remaining.first { remaining = remaining.dropFirst() }
        return remaining.isEmpty
    }

    /// Words that say nothing about WHICH title it is, so they cannot count towards a match.
    static let stopWords: Set<String> = ["the", "a", "an", "of", "and", "in", "on", "at", "to",
                                         "for", "with", "from", "by", "or", "is", "de", "la", "le",
                                         "el", "der", "die", "das"]

    /// The normalized words of a title, split on anything that is not a letter or digit.
    static func words(_ s: String) -> [String] {
        let folded = s.folding(options: [.diacriticInsensitive, .widthInsensitive],
                               locale: foldingLocale).lowercased()
        return folded.unicodeScalars
            .split { !CharacterSet.alphanumerics.contains($0) }
            .map { String(String.UnicodeScalarView($0)) }
    }

    /// Fold accents, lowercase, keep only alphanumerics (Unicode-aware, so Hebrew titles survive).
    /// Strips the punctuation/separators that differ between a TMDB title and a dotted release name.
    ///
    /// The accent fold is load-bearing. Scene releases spell accented titles in plain ASCII while
    /// TMDB stores the accents, and `é` is alphanumeric — so it survived normalization and
    /// "amélie" never contained "amelie". Every release of an accented title was therefore rejected
    /// as mis-attributed junk: the title listed no versions at all, and search could add nothing
    /// for it. Non-Latin scripts are unaffected — Hebrew has no accents to strip, and its combining
    /// marks were already dropped by the alphanumeric filter.
    ///
    /// The locale is pinned rather than taken from the system: Turkish folds `I`/`i` differently,
    /// which would make matching depend on the viewer's device language.
    private static let foldingLocale = Locale(identifier: "en_US_POSIX")

    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .widthInsensitive],
                               locale: foldingLocale)
        return String(String.UnicodeScalarView(folded.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }))
    }
}
