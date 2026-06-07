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
        let req = Self.normalize(title)
        guard !req.isEmpty else { return true }
        guard Self.normalize(parsed.title).contains(req) else { return false }

        if let want = year, let got = parsed.year {
            return abs(want - got) <= 1
        }
        if parsed.year == nil {
            return parsed.resolution != nil || parsed.source != nil
        }
        return true   // release has a year, request didn't — title gate already passed
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

    /// Lowercase, keep only alphanumerics (Unicode-aware, so Hebrew titles survive). Strips the
    /// punctuation/separators that differ between a TMDB title and a dotted release name.
    static func normalize(_ s: String) -> String {
        String(String.UnicodeScalarView(s.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }))
    }
}
