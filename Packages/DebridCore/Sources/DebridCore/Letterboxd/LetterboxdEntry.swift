import Foundation

/// One film as it appears in a Letterboxd profile grid.
public struct LetterboxdEntry: Sendable, Equatable {
    /// The join key for everything in this feature. Unique and stable on Letterboxd.
    public let slug: String
    /// The display name exactly as rendered, e.g. "Speed (1994)". Diagnostics only — never a match key.
    public let name: String
    public let year: Int?
    /// Letterboxd's own 1–10 value, nil when the film is logged but unrated.
    public let rating: Int?

    public init(slug: String, name: String, year: Int?, rating: Int?) {
        self.slug = slug
        self.name = name
        self.year = year
        self.rating = rating
    }
}
