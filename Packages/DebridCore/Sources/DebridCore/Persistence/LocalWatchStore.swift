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

    /// Fold `loser` into `winner`, then delete it.
    ///
    /// The rows a collapse resolves are not older and newer versions of one value — `rating`,
    /// `plays` and `lastWatchedAt` accumulate independently of the playback position, and a row
    /// can carry any of them while carrying none of the others. Deleting the loser outright, which
    /// is what every collapse used to do, therefore threw away a score the viewer typed on one
    /// device, undercounted their plays, and could drop a resume point when the surviving row
    /// happened to be a rating written on a device that never played the file.
    ///
    /// `winner` is the newest row, so it wins the fields that genuinely supersede — `finished`,
    /// and the position when it has one.
    ///
    /// One ambiguity is unresolvable without per-field timestamps: a rating CLEARED on the newer
    /// device looks identical to a rating never set there, so a duplicate can resurrect the old
    /// score. Losing a score outright is the worse and (until now) certain outcome.
    private func absorb(_ loser: WatchProgress, into winner: WatchProgress) {
        if winner.rating == nil { winner.rating = loser.rating }
        winner.plays = max(winner.plays, loser.plays)
        if let theirs = loser.lastWatchedAt {
            winner.lastWatchedAt = max(winner.lastWatchedAt ?? theirs, theirs)
        }
        if winner.positionSeconds == 0 && loser.positionSeconds > 0 {
            winner.positionSeconds = loser.positionSeconds
            if winner.sourceKey.isEmpty { winner.sourceKey = loser.sourceKey }
        }
        if winner.durationSeconds == 0 { winner.durationSeconds = loser.durationSeconds }
        modelContext.delete(loser)
    }

    /// The newest row for one title+profile, with every duplicate folded into it. `nil` when the
    /// title has no row at all.
    private func collapsed(_ contentKey: String, _ profileID: String) throws -> WatchProgress? {
        let existing = try rows(contentKey, profileID)
        guard let winner = existing.first else { return nil }
        for extra in existing.dropFirst() { absorb(extra, into: winner) }
        return winner
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
    /// after), the NEWER wins and the other is folded into it. Keeping both would leave every later
    /// read picking between duplicates by write order; deleting the loser outright — which is what
    /// this used to do — discarded whichever of the score, play count or resume point happened to
    /// live on the older row.
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
                // Fold every one of the owner's rows into the survivor, so a title that already
                // had duplicates does not keep them.
                for extra in existing.dropFirst() { absorb(extra, into: mine) }
                if orphan.updatedAt > mine.updatedAt {
                    orphan.profileID = owner
                    absorb(mine, into: orphan)
                } else {
                    absorb(orphan, into: mine)
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
        let row = try collapsed(contentKey, profileID) ?? {
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
        let row = try collapsed(contentKey, profileID) ?? {
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
    ///
    /// Every other read takes `.first` of a title's rows or collapses them; this one returned rows
    /// verbatim, so a title CloudKit had duplicated appeared in the rail twice — the same poster,
    /// side by side, at two different positions. De-duplicating by content key keeps the newest,
    /// which is the same rule every other reader applies.
    ///
    /// The fetch asks for more rows than requested because duplicates are removed afterwards:
    /// limiting first would return a short rail whenever any title had a duplicate.
    public func recent(limit: Int, profileID: String) throws -> [WatchState] {
        guard limit > 0 else { return [] }
        var descriptor = FetchDescriptor<WatchProgress>(
            predicate: #Predicate {
                $0.profileID == profileID && !$0.finished && $0.positionSeconds > 0
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = limit * 2 + 8
        var seen = Set<String>()
        var out: [WatchState] = []
        for row in try modelContext.fetch(descriptor) where seen.insert(row.contentKey).inserted {
            out.append(state(row))
            if out.count == limit { break }
        }
        return out
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

    /// Insert a row verbatim, bypassing the duplicate collapse. Exists so tests can reproduce what
    /// CloudKit hands us — two rows for one (title, profile) — which no public method can create.
    func seedRow(contentKey: String, profileID: String, sourceKey: String,
                 positionSeconds: Double, durationSeconds: Double, finished: Bool,
                 plays: Int, rating: Int?, updatedAt: Date, lastWatchedAt: Date?) throws {
        modelContext.insert(WatchProgress(contentKey: contentKey, profileID: profileID,
                                          sourceKey: sourceKey, positionSeconds: positionSeconds,
                                          durationSeconds: durationSeconds, finished: finished,
                                          plays: plays, rating: rating,
                                          updatedAt: updatedAt, lastWatchedAt: lastWatchedAt))
        try modelContext.save()
    }
}
#endif
