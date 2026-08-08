import DebridCore
import Foundation
import Observation

/// Owns the profile roster and the active selection for this app session. Normally we **always ask**
/// "Who's Watching?" on launch (Netflix-style): `loadAndResolve` leaves no profile selected, so the
/// gate shows until the user taps one. The roster syncs via CloudKit; the selection is per-session.
///
/// When `autoSelectsOwner` is set — which is what [`ProfilesFeature`] being off means — the gate is
/// skipped entirely and launch resolves to the oldest profile instead.
@MainActor
@Observable
public final class ActiveProfileStore {
    public private(set) var roster: [ProfileDTO] = []
    public private(set) var activeProfileID: String?

    /// The auto-created owner's avatar (a movie-night popcorn).
    public static let ownerAvatar = "🍿"

    private let provider: ProfileRosterProviding
    /// Resolve to the owner at launch rather than asking. Injected rather than read from
    /// `ProfilesFeature` here so both behaviours stay testable while the feature is off.
    private let autoSelectsOwner: Bool

    public init(provider: ProfileRosterProviding,
                autoSelectsOwner: Bool = !ProfilesFeature.isEnabled) {
        self.provider = provider
        self.autoSelectsOwner = autoSelectsOwner
    }

    public var activeProfile: ProfileDTO? { roster.first { $0.id == activeProfileID } }

    /// Show "Who's Watching?" whenever no profile is picked for this session — unless we resolve the
    /// owner ourselves, in which case there is nothing to ask. Deliberately `false` even on an empty
    /// roster: a profile container that failed to open would otherwise strand the viewer on a picker
    /// with no profiles to pick.
    public var needsSelection: Bool { autoSelectsOwner ? false : activeProfileID == nil }

    /// Ensure an owner profile exists (migrating Phase-1 progress) and load the roster, then either
    /// leave the selection empty so the launch picker is shown, or resolve it to the owner.
    ///
    /// The owner is `roster.first` — oldest by `createdAt`, the same row
    /// `ensureOwnerProfileAndMigrate` returns. It has to be that row and not any other: watch
    /// history, Continue Watching and My List are keyed by profile id, so resolving to a different
    /// profile would silently show an empty app.
    public func loadAndResolve() async {
        _ = try? await provider.ensureOwnerProfileAndMigrate(
            ownerName: "Me", colorTag: "gold", avatar: Self.ownerAvatar)
        roster = (try? await provider.all()) ?? []
        activeProfileID = autoSelectsOwner ? roster.first?.id : nil
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
