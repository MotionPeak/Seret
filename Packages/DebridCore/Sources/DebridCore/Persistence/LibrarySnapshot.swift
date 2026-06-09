import Foundation

/// The serializable, offline-capable form of the enriched library. Rebuildable from RD —
/// stored as a device-local file, never CloudKit-synced. Self-sufficient for display and
/// playback (quality lives in `MediaSource.parsed`; the play-time link is `MediaSource.restrictedLink`).
public struct LibrarySnapshot: Sendable, Equatable, Codable {
    public static let currentSchemaVersion = 2

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
