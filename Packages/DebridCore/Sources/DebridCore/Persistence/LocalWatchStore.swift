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

    /// Hand every row recorded with NO profile to `owner`.
    ///
    /// Progress can be written before a profile has resolved: the session signs in and only then
    /// kicks off the profile load, and the player captures whatever `activeProfileID` was at the
    /// moment it was built — the empty string, inside that window. Reads afterwards use the
    /// resolved id, and the fetch matches `profileID` exactly, so those rows become unreadable.
    /// The symptom is a title that offers "Play" instead of "Resume" and starts from zero even
    /// though it was watched, permanently, for whichever titles fell in the window.
    ///
    /// Idempotent — it runs on every launch, and after the first pass there is nothing to adopt.
    ///
    /// Where both rows exist for one title (watched once before the profile resolved and once
    /// after), the NEWER wins and the other is deleted. Keeping both would leave every later read
    /// picking between duplicates by write order.
    public func adoptUnprofiledProgress(into owner: String) throws {
        guard !owner.isEmpty else { return }
        let orphans = try modelContext.fetch(FetchDescriptor<WatchProgress>(
            predicate: #Predicate { $0.profileID == "" }))
        guard !orphans.isEmpty else { return }

        for orphan in orphans {
            let key = orphan.contentKey
            let existing = try modelContext.fetch(FetchDescriptor<WatchProgress>(
                predicate: #Predicate { $0.contentKey == key && $0.profileID == owner },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
            if let mine = existing.first {
                if orphan.updatedAt > mine.updatedAt {
                    modelContext.delete(mine)
                    orphan.profileID = owner
                } else {
                    modelContext.delete(orphan)
                }
            } else {
                orphan.profileID = owner
            }
        }
        try modelContext.save()
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

    public func rating(forContentKey key: String, profileID: String) throws -> Int? {
        try rows(key, profileID).first?.rating
    }

    /// Set or clear the viewer's 1–10 score, creating the row if the title has never been played.
    public func setRating(_ value: Int?, contentKey: String, profileID: String,
                          at: Date = Date()) throws {
        let existing = try rows(contentKey, profileID)
        for extra in existing.dropFirst() { modelContext.delete(extra) }
        let row = existing.first ?? {
            let r = WatchProgress(contentKey: contentKey, profileID: profileID)
            modelContext.insert(r); return r
        }()
        row.rating = value
        row.updatedAt = at
        try modelContext.save()
    }

    /// Completed plays + when it was last finished, for the title page. Nil when never watched.
    /// Returns a tuple, not a `WatchSummary`: that type lives in DebridUI, which depends on
    /// DebridCore and not the other way round.
    public func rollup(forContentKey key: String,
                       profileID: String) throws -> (plays: Int, lastWatchedAt: Date?)? {
        guard let row = try rows(key, profileID).first else { return nil }
        return (row.plays, row.lastWatchedAt)
    }

    /// Continue Watching for one profile: started, not finished, newest first.
    public func recent(limit: Int, profileID: String) throws -> [WatchState] {
        var descriptor = FetchDescriptor<WatchProgress>(
            predicate: #Predicate {
                $0.profileID == profileID && !$0.finished && $0.positionSeconds > 0
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(state)
    }

    /// Drop progress for these titles across every profile — the item left the shared library.
    public func delete(contentKeys keys: [String]) throws {
        for row in try modelContext.fetch(FetchDescriptor<WatchProgress>(
            predicate: #Predicate { keys.contains($0.contentKey) })) {
            modelContext.delete(row)
        }
        try modelContext.save()
    }

    public func count() throws -> Int {
        try modelContext.fetch(FetchDescriptor<WatchProgress>()).count
    }
}
#endif
