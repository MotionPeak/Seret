import Foundation
import SwiftData

/// SwiftData-backed watch-progress store. `@ModelActor` owns a `ModelContext` isolated to this
/// actor, so it is safe to use from any task under Swift 6 strict concurrency. Returns `Sendable`
/// `WatchState` values (never the `@Model` across the actor boundary).
@ModelActor
public actor WatchProgressStore {
    /// Most-recent position for a title under a profile, or `nil` if never played.
    public func progress(forContentKey key: String, profileID: String) throws -> WatchState? {
        try fetchOne(contentKey: key, profileID: profileID).map(WatchState.init)
    }

    /// Insert-or-update the single row for (`contentKey`, `profileID`) (CloudKit forbids a unique
    /// constraint, so we dedupe here). `at` is injectable for deterministic ordering in tests.
    public func record(contentKey: String, sourceKey: String,
                       positionSeconds: Double, durationSeconds: Double,
                       finished: Bool, profileID: String, at: Date = Date()) throws {
        let row = try fetchOne(contentKey: contentKey, profileID: profileID) ?? {
            let r = WatchProgress(contentKey: contentKey, profileID: profileID)
            modelContext.insert(r)
            return r
        }()
        row.sourceKey = sourceKey
        row.positionSeconds = positionSeconds
        row.durationSeconds = durationSeconds
        row.finished = finished
        row.profileID = profileID
        row.updatedAt = at
        try modelContext.save()
    }

    /// Continue-Watching feed for one profile: unfinished rows that have progress, newest first,
    /// **deduped by contentKey** (CloudKit can sync more than one row per key from different devices).
    public func recentlyWatched(limit: Int, profileID: String) throws -> [WatchState] {
        guard limit > 0 else { return [] }
        let rows = try modelContext.fetch(FetchDescriptor<WatchProgress>(
            predicate: #Predicate { $0.finished == false && $0.positionSeconds > 0
                                    && $0.profileID == profileID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
        var seen = Set<String>()
        var out: [WatchState] = []
        for row in rows where seen.insert(row.contentKey).inserted {   // newest-first → first wins
            out.append(WatchState(row))
            if out.count == limit { break }
        }
        return out
    }

    /// Delete the rows for these content keys (used when an item is removed from the library).
    /// No-op for an empty list.
    public func deleteProgress(forContentKeys keys: [String]) throws {
        guard !keys.isEmpty else { return }
        let keySet = Set(keys)
        let rows = try modelContext.fetch(FetchDescriptor<WatchProgress>())
            .filter { keySet.contains($0.contentKey) }
        for row in rows { modelContext.delete(row) }
        try modelContext.save()
    }

    /// Total row count — used by tests to assert upsert (not insert) behavior.
    func allCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<WatchProgress>())
    }

    /// Newest row for (`key`, `profileID`). If CloudKit merged duplicates, keep the newest
    /// (`updatedAt`) and delete the rest so the store converges to one row per key+profile.
    private func fetchOne(contentKey key: String, profileID: String) throws -> WatchProgress? {
        let matches = try modelContext.fetch(FetchDescriptor<WatchProgress>(
            predicate: #Predicate { $0.contentKey == key && $0.profileID == profileID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
        guard let survivor = matches.first else { return nil }
        if matches.count > 1 {
            for stale in matches.dropFirst() { modelContext.delete(stale) }
            try modelContext.save()
        }
        return survivor
    }
}
