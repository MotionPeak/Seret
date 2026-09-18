import Foundation

/// One film on the owner's Letterboxd watchlist.
///
/// `position` rather than a date because Letterboxd exposes no date-added: the watchlist page is
/// ordered newest-first and the position is that order, recorded at crawl time.
public struct WatchlistEntry: Sendable, Codable, Equatable, Identifiable {
    public var id: String { slug }
    public let slug: String
    /// The display name exactly as rendered, e.g. "Speed (1994)".
    public let name: String
    public let year: Int?
    /// 0 is the most recently added.
    public var position: Int
    public var tmdbID: Int?
    public var posterPath: String?
    /// When resolution last ran. Nil means never tried; non-nil with a nil `tmdbID` means it ran
    /// and found nothing — the two are different, and the UI says so.
    public var resolvedAt: Date?

    public var isResolved: Bool { resolvedAt != nil }

    public init(slug: String, name: String, year: Int?, position: Int,
                tmdbID: Int? = nil, posterPath: String? = nil, resolvedAt: Date? = nil) {
        self.slug = slug
        self.name = name
        self.year = year
        self.position = position
        self.tmdbID = tmdbID
        self.posterPath = posterPath
        self.resolvedAt = resolvedAt
    }
}
