import Foundation

/// A per-title rollup of the viewer's Trakt watch history.
public struct WatchSummary: Sendable, Equatable {
    public let plays: Int
    public let lastWatchedAt: Date?
    public init(plays: Int, lastWatchedAt: Date?) {
        self.plays = plays
        self.lastWatchedAt = lastWatchedAt
    }
}

/// An optional capability of a `WatchProgressProviding`: richer history for the Detail page.
/// `DetailStore` obtains it by conditionally casting the `watch` seam it already holds
/// (`watch as? WatchSummaryProviding`), exactly like `WatchRatingProviding` — so nothing
/// new is threaded through any initializer.
public protocol WatchSummaryProviding: Sendable {
    /// Play count + last-watched date, drawn from the already-fetched `/sync/watched` payloads.
    func watchSummary(forContentKey key: String) async -> WatchSummary?
    /// The earliest date this title appears in the viewer's Trakt history (one lazy network hop).
    /// Nil when unknown or unavailable.
    func historySince(forContentKey key: String) async -> Date?
}
