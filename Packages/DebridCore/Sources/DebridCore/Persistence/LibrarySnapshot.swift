import Foundation

/// The serializable, offline-capable form of the enriched library. Rebuildable from RD —
/// stored as a device-local file, never CloudKit-synced. Self-sufficient for display and
/// playback (quality lives in `MediaSource.parsed`; the play-time link is `MediaSource.restrictedLink`).
public struct LibrarySnapshot: Sendable, Equatable, Codable {
    /// Bump whenever the SHAPE of a snapshot changes — and equally whenever the way the library is
    /// GROUPED changes, because the snapshot stores already-grouped items.
    ///
    /// `LibrarySnapshotStore.load()` discards a snapshot whose version differs, which makes the next
    /// refresh see an empty cache and re-group every torrent from scratch. Without a bump, a parsing
    /// or grouping fix reaches only libraries that happen to gain or lose a torrent afterwards —
    /// `refresh()` returns the cached items untouched when nothing in RD changed, so an existing
    /// library can keep the old, wrong grouping indefinitely.
    ///
    /// 3: episode names with a separator (`S01.E01`) now parse as episodes, and a season RANGE
    /// (`S01-S04`) ends the title — so complete-series packs merge into their show instead of
    /// becoming a separate, unmatchable one.
    ///
    /// 4: a year inside a title is no longer mistaken for the release year ("Blade Runner 2049",
    /// "2012"), and a double episode (`S01E01E02`) parses as an episode instead of a movie. Both
    /// change the title a torrent groups under, so an existing library has to be re-grouped to
    /// pick them up.
    public static let currentSchemaVersion = 4

    public let schemaVersion: Int
    public let builtAt: Date
    public let items: [MediaItem]
    /// Every RD torrent id present at the last successful refresh — INCLUDING torrents that yield
    /// no item (non-video, empty). The delta check compares against this set, so a non-video
    /// torrent no longer looks perpetually "new" and force a full re-fetch on every launch.
    public let seenTorrentIDs: [String]

    /// The same torrents as `seenTorrentIDs`, but as `id:status` — because a torrent's id does not
    /// change while it downloads. Only its `status` does (`downloading` → `downloaded`), and that
    /// transition is precisely when a title becomes real. Comparing ids alone reports "nothing
    /// changed" for it, so a finished download never reached the library.
    ///
    /// `nil` in a snapshot written before this field existed, which forces exactly one delta so the
    /// states get recorded. That costs one `/torrents/info` fan-out and no TMDB calls (the cached
    /// metadata is carried), so there is no need to discard the snapshot with a schema bump.
    public let seenTorrentStates: [String]?

    public init(schemaVersion: Int = LibrarySnapshot.currentSchemaVersion,
                builtAt: Date = Date(), items: [MediaItem], seenTorrentIDs: [String] = [],
                seenTorrentStates: [String]? = nil) {
        self.schemaVersion = schemaVersion
        self.builtAt = builtAt
        self.items = items
        self.seenTorrentIDs = seenTorrentIDs
        self.seenTorrentStates = seenTorrentStates
    }
}
