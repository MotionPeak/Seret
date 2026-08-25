#if canImport(SwiftData)
import Foundation
import SwiftData

/// SwiftData-backed roster of viewer `Profile`s. `@ModelActor` isolates its `ModelContext`. Its
/// container also holds `MyListEntry` and `WatchProgress` so `delete` can cascade to everything
/// filed under a profile.
@ModelActor
public actor ProfileStore {
    /// All profiles, oldest first (creation order = display order), **deduped by id** — CloudKit
    /// can sync more than one row for the same id (e.g. two devices each bootstrapped the default
    /// owner before syncing); keep the earliest per id so the roster shows one entry.
    public func all() throws -> [ProfileDTO] {
        let rows = try modelContext.fetch(FetchDescriptor<Profile>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]))
        var seen = Set<String>()
        return rows.compactMap { seen.insert($0.id).inserted ? ProfileDTO($0) : nil }
    }

    /// Create a profile. `id`/`at` are injectable for deterministic tests.
    @discardableResult
    public func create(name: String, colorTag: String, avatar: String = "",
                       id: String = UUID().uuidString, at: Date = Date()) throws -> ProfileDTO {
        let p = Profile(id: id, name: name, colorTag: colorTag, avatar: avatar, createdAt: at)
        modelContext.insert(p)
        try modelContext.save()
        return ProfileDTO(p)
    }

    public func rename(id: String, to name: String) throws {
        guard let p = try fetchOne(id: id) else { return }
        p.name = name
        try modelContext.save()
    }

    /// Edit a profile's name, color, and avatar. No-op if the id doesn't exist.
    public func update(id: String, name: String, colorTag: String, avatar: String) throws {
        guard let p = try fetchOne(id: id) else { return }
        p.name = name
        p.colorTag = colorTag
        p.avatar = avatar
        try modelContext.save()
    }

    /// Delete a profile and cascade to everything filed under it: its My-List entries and its
    /// watch progress.
    ///
    /// The watch cascade was missing because this was written when history lived on Trakt, as one
    /// account for the whole app. Trakt is gone and watch state is per-profile and local, so every
    /// deleted profile left its rows behind for good — invisible, un-reachable, and syncing to
    /// every device forever. The confirmation dialog told the viewer this progress would be
    /// removed, which made it a promise the code did not keep.
    public func delete(id: String) throws {
        if let p = try fetchOne(id: id) { modelContext.delete(p) }
        for entry in try modelContext.fetch(FetchDescriptor<MyListEntry>(
            predicate: #Predicate { $0.profileID == id })) {
            modelContext.delete(entry)
        }
        for row in try modelContext.fetch(FetchDescriptor<WatchProgress>(
            predicate: #Predicate { $0.profileID == id })) {
            modelContext.delete(row)
        }
        try modelContext.save()
    }

    /// Idempotent first-launch setup: if any profile exists, return the earliest (the owner)
    /// untouched. Otherwise create an owner profile. (This used to also re-key legacy local watch
    /// rows onto the owner; watch state is Trakt's now, so there is nothing left to re-key.)
    @discardableResult
    public func ensureOwnerProfileAndMigrate(ownerName: String, colorTag: String, avatar: String = "",
                                             id: String = UUID().uuidString,
                                             at: Date = Date()) throws -> ProfileDTO {
        let existing = try modelContext.fetch(FetchDescriptor<Profile>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]))
        if let owner = existing.first { return ProfileDTO(owner) }

        let owner = Profile(id: id, name: ownerName, colorTag: colorTag, avatar: avatar, createdAt: at)
        modelContext.insert(owner)
        try modelContext.save()
        return ProfileDTO(owner)
    }

    private func fetchOne(id: String) throws -> Profile? {
        var d = FetchDescriptor<Profile>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }
}
#endif
