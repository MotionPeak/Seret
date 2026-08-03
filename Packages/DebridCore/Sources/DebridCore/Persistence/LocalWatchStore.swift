#if canImport(SwiftData)
import Foundation
import SwiftData

/// Local, CloudKit-synced watch state. `@ModelActor` isolates its `ModelContext`, so it is safe
/// from any task.
///
/// Method names deliberately avoid the `WatchProgressProviding` seam's spelling
/// (`progress`/`record`/`recentlyWatched`): `LocalWatchProvider` in DebridUI adapts this store to
/// that seam, and same-named throwing overloads are what made `VersionPreferenceStore`'s
/// conformance ambiguous.
@ModelActor
public actor LocalWatchStore {
    /// Rows for one title+profile, newest write first. More than one means CloudKit merged two
    /// devices; the caller takes `.first` and writers collapse the rest.
    private func rows(_ contentKey: String, _ profileID: String) throws -> [WatchProgress] {
        try modelContext.fetch(FetchDescriptor<WatchProgress>(
            predicate: #Predicate { $0.contentKey == contentKey && $0.profileID == profileID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
    }

    private func state(_ row: WatchProgress) -> WatchState {
        WatchState(contentKey: row.contentKey, sourceKey: row.sourceKey,
                   positionSeconds: row.positionSeconds, durationSeconds: row.durationSeconds,
                   finished: row.finished, updatedAt: row.updatedAt)
    }

    public func state(forContentKey key: String, profileID: String) throws -> WatchState? {
        try rows(key, profileID).first.map(state)
    }

    /// Every known state for these keys, in ONE fetch. Keys with no row are simply absent.
    public func states(forContentKeys keys: [String], profileID: String) throws -> [String: WatchState] {
        let rows = try modelContext.fetch(FetchDescriptor<WatchProgress>(
            predicate: #Predicate { keys.contains($0.contentKey) && $0.profileID == profileID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
        var out: [String: WatchState] = [:]
        // Newest-first ordering means the first row wins and later duplicates are ignored.
        for row in rows where out[row.contentKey] == nil { out[row.contentKey] = state(row) }
        return out
    }

    /// Record playback position (or a manual mark). Collapses any duplicate rows CloudKit produced.
    public func write(contentKey: String, sourceKey: String, positionSeconds: Double,
                      durationSeconds: Double, finished: Bool, profileID: String,
                      at: Date = Date()) throws {
        let existing = try rows(contentKey, profileID)
        for extra in existing.dropFirst() { modelContext.delete(extra) }
        let row = existing.first ?? {
            let r = WatchProgress(); modelContext.insert(r); return r
        }()
        let wasFinished = row.finished
        row.contentKey = contentKey
        row.profileID = profileID
        row.sourceKey = sourceKey
        row.positionSeconds = positionSeconds
        row.durationSeconds = durationSeconds
        row.finished = finished
        row.updatedAt = at
        // Count a play only on the unfinished→finished edge, so re-saving position on an already
        // watched title does not inflate the count.
        if finished {
            if !wasFinished { row.plays += 1 }
            row.lastWatchedAt = at
        }
        try modelContext.save()
    }

    public func count() throws -> Int {
        try modelContext.fetch(FetchDescriptor<WatchProgress>()).count
    }
}
#endif
