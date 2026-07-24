import DebridCore
import Foundation

/// The user's own 1–10 rating for a title, synced to the watch backend (Trakt).
///
/// Deliberately separate from `RatingsProviding`, which supplies the *aggregate* public scores
/// (IMDb / Rotten Tomatoes / Metacritic via OMDb). This one is personal and writable.
///
/// `DetailStore` picks this up by conditionally casting the `WatchProgressProviding` it is already
/// given — the Trakt provider implements both — so no call site has to thread a second dependency.
public protocol WatchRatingProviding: Sendable {
    func rating(forContentKey key: String) async -> Int?
    func setRating(_ value: Int?, forContentKey key: String) async
}

extension TraktWatchProvider: WatchRatingProviding {}
