import DebridCore
import Foundation
import Observation

/// Owns the profile roster and the active selection for this app session. We **always ask** "Who's
/// Watching?" on launch (Netflix-style): `loadAndResolve` leaves no profile selected, so the gate
/// shows until the user taps one. The roster syncs via CloudKit; the selection is per-session.
@MainActor
@Observable
public final class ActiveProfileStore {
    public private(set) var roster: [ProfileDTO] = []
    public private(set) var activeProfileID: String?

    /// The auto-created owner's avatar (a movie-night popcorn).
    public static let ownerAvatar = "🍿"

    private let provider: ProfileRosterProviding
    public init(provider: ProfileRosterProviding) { self.provider = provider }

    public var activeProfile: ProfileDTO? { roster.first { $0.id == activeProfileID } }

    /// Show "Who's Watching?" whenever no profile is picked for this session.
    public var needsSelection: Bool { activeProfileID == nil }

    /// Ensure an owner profile exists (migrating Phase-1 progress) and load the roster, then leave
    /// the selection empty so the launch picker is shown.
    public func loadAndResolve() async {
        _ = try? await provider.ensureOwnerProfileAndMigrate(
            ownerName: "Me", colorTag: "gold", avatar: Self.ownerAvatar)
        roster = (try? await provider.all()) ?? []
        activeProfileID = nil
    }

    /// Refresh the roster (e.g. after a CloudKit import) WITHOUT changing the active selection,
    /// so a profile created on another device appears here too.
    public func reloadRoster() async {
        roster = (try? await provider.all()) ?? roster
    }

    public func select(_ id: String) {
        guard roster.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
    }

    /// Deselect to re-show "Who's Watching?" (the Switch-Profile action).
    public func switchProfile() { activeProfileID = nil }

    public func create(name: String, colorTag: String, avatar: String) async {
        _ = try? await provider.create(name: name, colorTag: colorTag, avatar: avatar)
        roster = (try? await provider.all()) ?? roster
    }

    public func rename(id: String, to name: String) async {
        try? await provider.rename(id: id, to: name)
        roster = (try? await provider.all()) ?? roster
    }

    public func update(id: String, name: String, colorTag: String, avatar: String) async {
        try? await provider.update(id: id, name: name, colorTag: colorTag, avatar: avatar)
        roster = (try? await provider.all()) ?? roster
    }

    public func delete(id: String) async {
        try? await provider.delete(id: id)
        if activeProfileID == id { activeProfileID = nil }
        roster = (try? await provider.all()) ?? roster
    }
}
