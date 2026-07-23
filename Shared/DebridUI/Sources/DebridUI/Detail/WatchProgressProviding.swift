import DebridCore
import Foundation

/// Sendable seam over `WatchProgressStore` so `DetailStore` reads/writes progress without
/// pulling SwiftData into the app's unit tests.
public protocol WatchProgressProviding: Sendable {
    func progress(forContentKey key: String, profileID: String) async throws -> WatchState?
    /// Batched read: states for many keys at once (a season's episodes). Declared as a
    /// requirement so `WatchProgressStore`'s single-fetch implementation is used through the
    /// seam; everything else (fakes, no-op stores) falls back to the per-key default below.
    func progress(forContentKeys keys: [String], profileID: String) async throws -> [String: WatchState]
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws
    /// Continue-Watching feed for one profile: unfinished rows with progress, newest first.
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState]
    /// Delete progress rows for the given content keys across all profiles (item removed from the
    /// shared library).
    func deleteProgress(forContentKeys keys: [String]) async throws
}

extension WatchProgressProviding {
    /// Default batched read: one `progress(forContentKey:)` call per key. Correct everywhere;
    /// stores with a real batch fetch override it for one round-trip.
    public func progress(forContentKeys keys: [String], profileID: String) async throws -> [String: WatchState] {
        var out: [String: WatchState] = [:]
        for key in keys {
            out[key] = try await progress(forContentKey: key, profileID: profileID)
        }
        return out
    }

    /// Manually mark a movie/episode watched or unwatched. A manual mark carries no playback
    /// position — `finished` alone drives the UI (full bar / ✓); live position is written later by
    /// the player. Shared by `DetailStore` (per-title) and `LibraryStore` (grid long-press) so the
    /// record shape stays in one place.
    public func setWatched(_ watched: Bool, contentKey: String, source: MediaSource,
                           profileID: String) async {
        try? await record(contentKey: contentKey, sourceKey: WatchKey.source(source),
                          positionSeconds: 0, durationSeconds: 0, finished: watched, profileID: profileID)
    }
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
