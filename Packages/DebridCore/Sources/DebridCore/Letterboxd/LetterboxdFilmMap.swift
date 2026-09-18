import Foundation

/// Remembers which Letterboxd film a TMDB id is, so a resolution is paid for once.
///
/// This is the join key for both sync directions: the pull reads slugs out of the profile grid and
/// the push needs a slug to write to. Slugs are stable on Letterboxd, so entries never expire.
public actor LetterboxdFilmMap {
    private var slugs: [Int: String]

    public init(seed: [Int: String] = [:]) { self.slugs = seed }

    public func slug(forTMDB id: Int) -> String? { slugs[id] }
    public func store(_ slug: String, forTMDB id: Int) { slugs[id] = slug }
    public func snapshot() -> [Int: String] { slugs }
}
