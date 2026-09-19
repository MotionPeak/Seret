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

    /// When the owner added this film in Seret, if Letterboxd did not have it first.
    ///
    /// A crawled entry leaves this nil forever: it says "this row started here", which is what
    /// decides whether a crawl that lacks the film means it was never sent or that it has gone.
    public var addedLocallyAt: Date?

    /// When the add was accepted by Letterboxd, if it has been.
    ///
    /// Symmetrical with `removalPushedAt`, and pending is derived the same way — the mirror is the
    /// only durable record, so a parallel queue could only drift from it.
    public var addPushedAt: Date?

    public var isResolved: Bool { resolvedAt != nil }
    public var isRemoved: Bool { removedAt != nil }
    /// Removed here, but Letterboxd has not been told yet.
    public var needsRemovalPush: Bool { removedAt != nil && removalPushedAt == nil }

    /// Added here rather than crawled. Such a row is carried across merges until Letterboxd has
    /// been told about it, because a crawl cannot contain a film that was never sent.
    public var isLocalAdd: Bool { addedLocallyAt != nil }
    /// Added here, and Letterboxd has not been told yet.
    public var needsAddPush: Bool { addedLocallyAt != nil && addPushedAt == nil }

    /// The identity a locally-added film carries until a crawl supplies the real one.
    ///
    /// A film added in Seret has a TMDB id and no slug: the slug lives behind `/tmdb/{id}/` on
    /// letterboxd.com, which Cloudflare refuses to every client that is not a real browser — so
    /// the device cannot learn it, and the push does not need it (the server resolves it there).
    /// Prefixed rather than bare so it can never collide with a real Letterboxd slug.
    public static func localSlug(forTMDB id: Int) -> String { "tmdb-\(id)" }

    public init(slug: String, name: String, year: Int?, position: Int,
                tmdbID: Int? = nil, posterPath: String? = nil, resolvedAt: Date? = nil,
                removedAt: Date? = nil, removalPushedAt: Date? = nil,
                addedLocallyAt: Date? = nil, addPushedAt: Date? = nil) {
        self.slug = slug
        self.name = name
        self.year = year
        self.position = position
        self.tmdbID = tmdbID
        self.posterPath = posterPath
        self.resolvedAt = resolvedAt
        self.removedAt = removedAt
        self.removalPushedAt = removalPushedAt
        self.addedLocallyAt = addedLocallyAt
        self.addPushedAt = addPushedAt
    }

    /// A film the owner added in Seret, before Letterboxd knows anything about it.
    ///
    /// `name` carries the year the way a crawled name does ("Speed (1994)"), because every screen
    /// strips it back off with `WatchlistName.stripYear(from:)` — a local add that omitted it would
    /// read differently from every other tile.
    ///
    /// The position is the caller's: a just-added film is the newest, and Letterboxd lists newest
    /// first, so it belongs in front of everything already stored.
    public static func locallyAdded(tmdbID: Int, title: String, year: Int?, posterPath: String?,
                                   position: Int, at when: Date = Date()) -> WatchlistEntry {
        WatchlistEntry(slug: localSlug(forTMDB: tmdbID),
                       name: year.map { "\(title) (\($0))" } ?? title,
                       year: year,
                       position: position,
                       tmdbID: tmdbID,
                       posterPath: posterPath,
                       // Nothing to resolve: the id is where this row came from.
                       resolvedAt: when,
                       addedLocallyAt: when)
    }
}
