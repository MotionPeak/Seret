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

    /// When the owner removed this film in Seret, if they have.
    ///
    /// The film stays in the mirror rather than being deleted from it: a crawl is the whole truth
    /// about what Letterboxd holds, so an entry simply dropped here would be handed straight back
    /// by the next sync. The mark is what makes a removal hold. A date rather than a flag because
    /// the eventual push to Letterboxd will want to know when it was asked for.
    ///
    /// Optional, so a mirror written before this field existed still decodes — the synthesised
    /// `Decodable` reads an optional with `decodeIfPresent`.
    public var removedAt: Date?

    /// When the removal was successfully pushed to Letterboxd, if it has been.
    ///
    /// The pending set is derived from the mirror rather than kept in a parallel queue: the mirror
    /// is already durable and already records the removal, so a second store could only drift from
    /// it. A removal that has never been pushed stays pending until it succeeds, which makes the
    /// retry self-healing without any backoff bookkeeping.
    public var removalPushedAt: Date?

    public var isResolved: Bool { resolvedAt != nil }
    public var isRemoved: Bool { removedAt != nil }
    /// Removed here, but Letterboxd has not been told yet.
    public var needsRemovalPush: Bool { removedAt != nil && removalPushedAt == nil }

    public init(slug: String, name: String, year: Int?, position: Int,
                tmdbID: Int? = nil, posterPath: String? = nil, resolvedAt: Date? = nil,
                removedAt: Date? = nil, removalPushedAt: Date? = nil) {
        self.slug = slug
        self.name = name
        self.year = year
        self.position = position
        self.tmdbID = tmdbID
        self.posterPath = posterPath
        self.resolvedAt = resolvedAt
        self.removedAt = removedAt
        self.removalPushedAt = removalPushedAt
    }
}
