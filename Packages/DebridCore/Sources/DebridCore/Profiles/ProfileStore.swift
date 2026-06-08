import Foundation
import SwiftData

/// SwiftData-backed roster of viewer `Profile`s. `@ModelActor` isolates its `ModelContext`. Its
/// container also holds `MyListEntry` + `WatchProgress` so `delete` can cascade and the owner
/// migration can re-key existing progress.
@ModelActor
public actor ProfileStore {
    /// All profiles, oldest first (creation order = display order).
    public func all() throws -> [ProfileDTO] {
        try modelContext.fetch(FetchDescriptor<Profile>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)])).map(ProfileDTO.init)
    }

    /// Create a profile. `id`/`at` are injectable for deterministic tests.
    @discardableResult
    public func create(name: String, colorTag: String,
                       id: String = UUID().uuidString, at: Date = Date()) throws -> ProfileDTO {
        let p = Profile(id: id, name: name, colorTag: colorTag, createdAt: at)
        modelContext.insert(p)
        try modelContext.save()
        return ProfileDTO(p)
    }

    public func rename(id: String, to name: String) throws {
        guard let p = try fetchOne(id: id) else { return }
        p.name = name
        try modelContext.save()
    }

    private func fetchOne(id: String) throws -> Profile? {
        var d = FetchDescriptor<Profile>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }
}
