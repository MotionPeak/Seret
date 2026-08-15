import DebridCore
import Foundation

/// The user's own 1–10 rating for a title, held in the on-device watch state.
///
/// Deliberately separate from `RatingsProviding`, which supplies the *aggregate* public scores
/// (IMDb / Rotten Tomatoes / Metacritic via OMDb). This one is personal and writable.
///
/// `DetailStore` picks this up by conditionally casting the `WatchProgressProviding` it is already
/// given — the local provider implements both — so no call site threads a second dependency.
public protocol WatchRatingProviding: Sendable {
    func rating(forContentKey key: String) async -> Int?
    func setRating(_ value: Int?, forContentKey key: String) async
}
