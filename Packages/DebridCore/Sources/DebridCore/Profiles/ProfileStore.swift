import Foundation
import SwiftData

/// SwiftData-backed roster of viewer `Profile`s. `@ModelActor` isolates its `ModelContext`. Its
/// container also holds `MyListEntry` + `WatchProgress` so `delete` can cascade and the owner
/// migration can re-key existing progress.
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

    /// Delete a profile and cascade to its My-List entries and watch progress.
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

    /// Idempotent first-launch migration: if any profile exists, return the earliest (the owner)
    /// untouched. Otherwise create an owner profile and re-key every `profileID == nil`
    /// `WatchProgress` row to it, so Phase-1 progress is preserved under the new profile model.
    @discardableResult
    public func ensureOwnerProfileAndMigrate(ownerName: String, colorTag: String, avatar: String = "",
                                             id: String = UUID().uuidString,
                                             at: Date = Date()) throws -> ProfileDTO {
        let existing = try modelContext.fetch(FetchDescriptor<Profile>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]))
        if let owner = existing.first { return ProfileDTO(owner) }

        let owner = Profile(id: id, name: ownerName, colorTag: colorTag, avatar: avatar, createdAt: at)
        modelContext.insert(owner)
        for row in try modelContext.fetch(FetchDescriptor<WatchProgress>(
            predicate: #Predicate { $0.profileID == nil })) {
            row.profileID = id
        }
        try modelContext.save()
        return ProfileDTO(owner)
    }

    private func fetchOne(id: String) throws -> Profile? {
        var d = FetchDescriptor<Profile>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }
}
