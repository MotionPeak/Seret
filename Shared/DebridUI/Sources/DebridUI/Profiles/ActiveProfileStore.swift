import DebridCore
import Foundation
import Observation

/// Owns the profile roster and the **device-local** active selection (Netflix-style: the roster
/// syncs via CloudKit, the selection does not). Drives the "Who's Watching?" gate.
@MainActor
@Observable
public final class ActiveProfileStore {
    public private(set) var roster: [ProfileDTO] = []
    public private(set) var activeProfileID: String?

    private let provider: ProfileRosterProviding
    private let defaults: UserDefaults
    private static let key = "seret.activeProfileID"

    public init(provider: ProfileRosterProviding, defaults: UserDefaults = .standard) {
        self.provider = provider
        self.defaults = defaults
    }

    public var activeProfile: ProfileDTO? { roster.first { $0.id == activeProfileID } }

    /// Show "Who's Watching?" when there are multiple profiles and this device hasn't resolved one.
    public var needsSelection: Bool { roster.count > 1 && activeProfile == nil }

    /// Ensure an owner profile exists (migrating Phase-1 progress), load the roster, and resolve the
    /// device-stored selection. Solo/owner-only → auto-select (no gate); multiple with no valid
    /// stored selection → leave unselected to force the gate.
    public func loadAndResolve() async {
        let owner = try? await provider.ensureOwnerProfileAndMigrate(ownerName: "Me", colorTag: "gold")
        roster = (try? await provider.all()) ?? []
        let stored = defaults.string(forKey: Self.key)
        if let stored, roster.contains(where: { $0.id == stored }) {
            activeProfileID = stored
        } else if roster.count <= 1 {
            activeProfileID = roster.first?.id ?? owner?.id
            persist()
        } else {
            activeProfileID = nil
        }
    }

    public func select(_ id: String) {
        guard roster.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
        persist()
    }

    /// Deselect to re-show "Who's Watching?" (the Switch-Profile action).
    public func switchProfile() {
        activeProfileID = nil
        defaults.removeObject(forKey: Self.key)
    }

    public func create(name: String, colorTag: String) async {
        _ = try? await provider.create(name: name, colorTag: colorTag)
        roster = (try? await provider.all()) ?? roster
    }

    public func rename(id: String, to name: String) async {
        try? await provider.rename(id: id, to: name)
        roster = (try? await provider.all()) ?? roster
    }

    public func delete(id: String) async {
        try? await provider.delete(id: id)
        if activeProfileID == id { switchProfile() }
        roster = (try? await provider.all()) ?? roster
    }

    private func persist() {
        if let id = activeProfileID { defaults.set(id, forKey: Self.key) }
    }
}
