import DebridCore
import Foundation

/// An optional capability of a `WatchProgressProviding`: the Trakt community score.
/// Obtained by casting the `watch` seam (`watch as? CommunityRatingProviding`).
public protocol CommunityRatingProviding: Sendable {
    /// The community average (0–10) for a title, addressed by IMDb id. Nil when unavailable.
    func communityRating(imdbID: String, kind: MediaKind) async -> Double?
}
