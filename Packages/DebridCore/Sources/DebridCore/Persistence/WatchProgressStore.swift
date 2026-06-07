import Foundation
import SwiftData

/// SwiftData-backed watch-progress store. `@ModelActor` owns a `ModelContext` isolated to this
/// actor, so it is safe to use from any task under Swift 6 strict concurrency. Returns `Sendable`
/// `WatchState` values (never the `@Model` across the actor boundary).
@ModelActor
public actor WatchProgressStore {
    /// Most-recent position for a title, or `nil` if never played.
    public func progress(forContentKey key: String) throws -> WatchState? {
        try fetchOne(contentKey: key).map(WatchState.init)
    }

    /// Insert-or-update the single row for `contentKey` (CloudKit forbids a unique constraint,
    /// so we dedupe here). `at` is injectable for deterministic ordering in tests.
    public func record(contentKey: String, sourceKey: String,
                       positionSeconds: Double, durationSeconds: Double,
                       finished: Bool, at: Date = Date()) throws {
        let row = try fetchOne(contentKey: contentKey) ?? {
            let r = WatchProgress(contentKey: contentKey)
            modelContext.insert(r)
            return r
        }()
        row.sourceKey = sourceKey
        row.positionSeconds = positionSeconds
        row.durationSeconds = durationSeconds
        row.finished = finished
        row.updatedAt = at
        try modelContext.save()
    }

    /// Continue-Watching feed: unfinished rows that have progress, newest first.
    public func recentlyWatched(limit: Int) throws -> [WatchState] {
        guard limit > 0 else { return [] }
        var descriptor = FetchDescriptor<WatchProgress>(
            predicate: #Predicate { $0.finished == false && $0.positionSeconds > 0 },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(WatchState.init)
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

    private func fetchOne(contentKey key: String) throws -> WatchProgress? {
        var descriptor = FetchDescriptor<WatchProgress>(
            predicate: #Predicate { $0.contentKey == key })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
