#if canImport(SwiftData)
import Foundation
import SwiftData

/// One viewer's watch state for one title.
///
/// CloudKit-ready: every property defaulted or optional, no unique constraint (CloudKit forbids
/// both). Logical identity is `(contentKey, profileID)`, which CloudKit cannot enforce — two
/// devices can each insert a row for the same title, so `LocalWatchStore` reads newest-first and
/// collapses duplicates on write.
@Model
public final class WatchProgress {
    /// `WatchKey.content(forMovie:)` / `WatchKey.content(forShow:episode:)`.
    public var contentKey: String = ""
    /// Which viewer this belongs to. Trakt had one history for everyone; local state is per profile.
    public var profileID: String = ""
    /// `WatchKey.source(_:)` — the exact file played.
    public var sourceKey: String = ""
    /// Real seconds. Trakt only ever gave a percentage, so this is strictly more than it could.
    public var positionSeconds: Double = 0
    public var durationSeconds: Double = 0
    public var finished: Bool = false
    /// Completed plays, for the title page's rollup. Incremented on each unfinished→finished edge.
    public var plays: Int = 0
    /// The viewer's own 1–10 score. Nil means unrated.
    public var rating: Int?
    /// Last write of any kind — the tiebreaker when CloudKit hands us duplicate rows.
    public var updatedAt: Date = Date(timeIntervalSince1970: 0)
    /// Last time this finished playing. Nil until it has been finished once.
    public var lastWatchedAt: Date?

    public init(contentKey: String = "", profileID: String = "", sourceKey: String = "",
                positionSeconds: Double = 0, durationSeconds: Double = 0,
                finished: Bool = false, plays: Int = 0, rating: Int? = nil,
                updatedAt: Date = Date(timeIntervalSince1970: 0), lastWatchedAt: Date? = nil) {
        self.contentKey = contentKey
        self.profileID = profileID
        self.sourceKey = sourceKey
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.finished = finished
        self.plays = plays
        self.rating = rating
        self.updatedAt = updatedAt
        self.lastWatchedAt = lastWatchedAt
    }
}
#endif
