import DebridCore
import Foundation

/// Sendable seam over `ProfileStore` so `ActiveProfileStore` is testable host-free (no SwiftData).
public protocol ProfileRosterProviding: Sendable {
    func all() async throws -> [ProfileDTO]
    func ensureOwnerProfileAndMigrate(ownerName: String, colorTag: String, avatar: String) async throws -> ProfileDTO
    func create(name: String, colorTag: String, avatar: String) async throws -> ProfileDTO
    func rename(id: String, to name: String) async throws
    func delete(id: String) async throws
}

extension ProfileStore: ProfileRosterProviding {
    // `all()` / `rename(id:to:)` / `delete(id:)` satisfy the requirements directly. Provide the
    // no-default overloads for the two factory methods (the store's take injectable id/at).
    public func create(name: String, colorTag: String, avatar: String) async throws -> ProfileDTO {
        try create(name: name, colorTag: colorTag, avatar: avatar, id: UUID().uuidString, at: Date())
    }
    public func ensureOwnerProfileAndMigrate(ownerName: String, colorTag: String, avatar: String) async throws -> ProfileDTO {
        // Stable id (NOT random) so every device converges on the same owner — the fix for watch
        // progress not lining up across devices.
        try ensureOwnerProfileAndMigrate(ownerName: ownerName, colorTag: colorTag, avatar: avatar,
                                         id: Profile.defaultOwnerID, at: Date())
    }
}
