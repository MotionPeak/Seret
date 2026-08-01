#if canImport(SwiftData)
import Foundation
import SwiftData

/// Which version of a title the user chose to play by default, overriding the quality ranker.
///
/// CloudKit-ready: every property defaulted, no unique constraint (CloudKit forbids both), so two
/// devices can write a row for the same title — `VersionPreferenceStore` reconciles last-write-wins.
@Model
public final class VersionPreference {
    public var contentKey: String = ""
    /// `WatchKey.source(_:)` — the torrent id and file id of the exact chosen file.
    public var sourceKey: String = ""
    public var chosenAt: Date = Date(timeIntervalSince1970: 0)

    public init(contentKey: String = "", sourceKey: String = "",
                chosenAt: Date = Date(timeIntervalSince1970: 0)) {
        self.contentKey = contentKey
        self.sourceKey = sourceKey
        self.chosenAt = chosenAt
    }
}
#endif
