import Foundation

/// The serializable, offline-capable form of the enriched library. Rebuildable from RD —
/// stored as a device-local file, never CloudKit-synced. Self-sufficient for display and
/// playback (quality lives in `MediaSource.parsed`; the play-time link is `MediaSource.restrictedLink`).
public struct LibrarySnapshot: Sendable, Equatable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let builtAt: Date
    public let items: [MediaItem]

    public init(schemaVersion: Int = LibrarySnapshot.currentSchemaVersion,
                builtAt: Date = Date(), items: [MediaItem]) {
        self.schemaVersion = schemaVersion
        self.builtAt = builtAt
        self.items = items
    }
}
