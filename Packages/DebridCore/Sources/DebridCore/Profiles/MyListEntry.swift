#if canImport(SwiftData)
import Foundation
import SwiftData

/// A title a profile has claimed into its "My List" (by Add or Play). One row per
/// (profile, title). CloudKit-ready: defaulted properties, no unique constraint — `id` is the
/// deterministic `"<profileID>|<contentKey>"` so claims are idempotent and dedupe is explicit.
@Model
public final class MyListEntry {
    public var id: String = ""
    public var profileID: String = ""
    public var contentKey: String = ""
    public var addedAt: Date = Date(timeIntervalSince1970: 0)

    public init(id: String = "", profileID: String = "", contentKey: String = "",
                addedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.id = id
        self.profileID = profileID
        self.contentKey = contentKey
        self.addedAt = addedAt
    }

    /// The deterministic primary key for a claim.
    public static func makeID(profileID: String, contentKey: String) -> String {
        "\(profileID)|\(contentKey)"
    }
}
#endif
