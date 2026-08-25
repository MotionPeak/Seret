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
    /// position of its own — `finished` alone drives the UI (full bar / ✓). Shared by `DetailStore`
    /// (per-title) and `LibraryStore` (grid long-press) so the record shape stays in one place.
    /// `sourceKey` is empty for a title you do not own: there is no file to name, and nothing
    /// downstream keys off it — watch state and download state both address a title by `contentKey`.
    ///
    /// Marking WATCHED carries the existing position and duration forward. It used to write zeros,
    /// which meant a long-press — easy to hit by accident on a grid tile — permanently destroyed
    /// the resume point of whatever it landed on, and un-marking could not bring back a position
    /// that was no longer stored. It also zeroed the duration every progress bar divides by.
    ///
    /// Marking UNWATCHED does clear the position, which is what "start over" means; carrying a
    /// past-the-threshold position into that write would also let the finished-fraction rule in
    /// `record` flip `finished` straight back to true.
    public func setWatched(_ watched: Bool, contentKey: String, sourceKey: String,
                           profileID: String) async {
        let carried = try? await progress(forContentKey: contentKey, profileID: profileID)
        try? await record(contentKey: contentKey,
                          sourceKey: sourceKey.isEmpty ? (carried?.sourceKey ?? "") : sourceKey,
                          // Position only when marking WATCHED — un-marking is "start over".
                          positionSeconds: watched ? (carried?.positionSeconds ?? 0) : 0,
                          // Duration always. It costs nothing (a position of 0 is 0% of any
                          // runtime, and the finished-fraction rule reads 0 either way), and it is
                          // what tells a deliberately un-marked row apart from a rating written on
                          // a device that never played the file — two shapes that were otherwise
                          // identical, so collapsing duplicates could silently undo the un-marking.
                          durationSeconds: carried?.durationSeconds ?? 0,
                          finished: watched,
                          profileID: profileID)
    }

    /// The owned form — names the exact file that was watched.
    public func setWatched(_ watched: Bool, contentKey: String, source: MediaSource,
                           profileID: String) async {
        await setWatched(watched, contentKey: contentKey, sourceKey: WatchKey.source(source),
                         profileID: profileID)
    }
}

// `LocalWatchProvider` is the only implementation of this seam in the app: it is the watch-state
// source of truth, and outlived the Trakt mirror that used to sit beside it.
