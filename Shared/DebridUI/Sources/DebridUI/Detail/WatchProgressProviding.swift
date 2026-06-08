import DebridCore
import Foundation

/// Sendable seam over `WatchProgressStore` so `DetailStore` reads/writes progress without
/// pulling SwiftData into the app's unit tests.
public protocol WatchProgressProviding: Sendable {
    func progress(forContentKey key: String, profileID: String) async throws -> WatchState?
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws
    /// Continue-Watching feed for one profile: unfinished rows with progress, newest first.
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState]
    /// Delete progress rows for the given content keys across all profiles (item removed from the
    /// shared library).
    func deleteProgress(forContentKeys keys: [String]) async throws
}

extension WatchProgressStore: WatchProgressProviding {
    // `progress(forContentKey:profileID:)` and `recentlyWatched(limit:profileID:)` satisfy the
    // requirements directly. Provide the no-`at:` `record` overload the seam declares.
    public func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                       durationSeconds: Double, finished: Bool, profileID: String) throws {
        try record(contentKey: contentKey, sourceKey: sourceKey, positionSeconds: positionSeconds,
                   durationSeconds: durationSeconds, finished: finished, profileID: profileID,
                   at: Date())
    }
}
