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
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public let builtAt: Date
    public let items: [MediaItem]
    /// Every RD torrent id present at the last successful refresh — INCLUDING torrents that yield
    /// no item (non-video, empty). The delta check compares against this set, so a non-video
    /// torrent no longer looks perpetually "new" and force a full re-fetch on every launch.
    public let seenTorrentIDs: [String]

    public init(schemaVersion: Int = LibrarySnapshot.currentSchemaVersion,
                builtAt: Date = Date(), items: [MediaItem], seenTorrentIDs: [String] = []) {
        self.schemaVersion = schemaVersion
        self.builtAt = builtAt
        self.items = items
        self.seenTorrentIDs = seenTorrentIDs
    }
}
