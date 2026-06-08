import Foundation
import SwiftData

/// SwiftData-backed per-profile "My List" of claimed titles. `@ModelActor` isolates its context.
/// Claims are keyed by the deterministic `MyListEntry.id`, so claiming is an idempotent upsert and
/// CloudKit-merged duplicates are reconciled on read (keep one, newest `addedAt`).
@ModelActor
public actor MyListStore {
    /// Claim a title for a profile (upsert by deterministic id; refreshes `addedAt`).
    public func claim(profileID: String, contentKey: String, at: Date = Date()) throws {
        let id = MyListEntry.makeID(profileID: profileID, contentKey: contentKey)
        let row = try fetchOne(id: id) ?? {
            let e = MyListEntry(id: id, profileID: profileID, contentKey: contentKey)
            modelContext.insert(e)
            return e
        }()
        row.addedAt = at
        try modelContext.save()
    }

    public func unclaim(profileID: String, contentKey: String) throws {
        let id = MyListEntry.makeID(profileID: profileID, contentKey: contentKey)
        for row in try modelContext.fetch(FetchDescriptor<MyListEntry>(
            predicate: #Predicate { $0.id == id })) {
            modelContext.delete(row)
        }
        try modelContext.save()
    }

    public func isClaimed(profileID: String, contentKey: String) throws -> Bool {
        let id = MyListEntry.makeID(profileID: profileID, contentKey: contentKey)
        return try fetchOne(id: id) != nil
    }

    /// Claimed content keys for a profile, newest first, deduped by content key.
    public func contentKeys(forProfile profileID: String) throws -> [String] {
        let rows = try modelContext.fetch(FetchDescriptor<MyListEntry>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]))
        var seen = Set<String>()
        return rows.compactMap { seen.insert($0.contentKey).inserted ? $0.contentKey : nil }
    }

    /// Newest row for an id; if CloudKit merged duplicates, keep the newest and delete the rest.
    private func fetchOne(id: String) throws -> MyListEntry? {
        let matches = try modelContext.fetch(FetchDescriptor<MyListEntry>(
            predicate: #Predicate { $0.id == id },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]))
        guard let survivor = matches.first else { return nil }
        if matches.count > 1 {
            for stale in matches.dropFirst() { modelContext.delete(stale) }
            try modelContext.save()
        }
        return survivor
    }
}
