import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// In-memory roster fake. `actor` for Sendable conformance.
private actor FakeRoster: ProfileRosterProviding {
    private var rows: [ProfileDTO]
    init(_ rows: [ProfileDTO] = []) { self.rows = rows }
    func all() async throws -> [ProfileDTO] { rows.sorted { $0.createdAt < $1.createdAt } }
    func ensureOwnerProfileAndMigrate(ownerName: String, colorTag: String, avatar: String) async throws -> ProfileDTO {
        if let owner = rows.sorted(by: { $0.createdAt < $1.createdAt }).first { return owner }
        let owner = ProfileDTO(id: "owner", name: ownerName, colorTag: colorTag, avatar: avatar,
                               createdAt: Date(timeIntervalSince1970: 0))
        rows.append(owner)
        return owner
    }
    func create(name: String, colorTag: String, avatar: String) async throws -> ProfileDTO {
        let p = ProfileDTO(id: "id\(rows.count)", name: name, colorTag: colorTag, avatar: avatar,
                           createdAt: Date(timeIntervalSince1970: Double(rows.count + 1)))
        rows.append(p); return p
    }
    func rename(id: String, to name: String) async throws {
        if let i = rows.firstIndex(where: { $0.id == id }) {
            rows[i] = ProfileDTO(id: id, name: name, colorTag: rows[i].colorTag,
                                 avatar: rows[i].avatar, createdAt: rows[i].createdAt)
        }
    }
    func update(id: String, name: String, colorTag: String, avatar: String) async throws {
        if let i = rows.firstIndex(where: { $0.id == id }) {
            rows[i] = ProfileDTO(id: id, name: name, colorTag: colorTag, avatar: avatar, createdAt: rows[i].createdAt)
        }
    }
    func delete(id: String) async throws { rows.removeAll { $0.id == id } }
}

/// Stands in for a profile container that failed to open: every call throws, so the roster stays
/// empty and there is no owner to fall back on.
private actor EmptyRoster: ProfileRosterProviding {
    private struct Unavailable: Error {}
    func all() async throws -> [ProfileDTO] { throw Unavailable() }
    func ensureOwnerProfileAndMigrate(ownerName: String, colorTag: String, avatar: String) async throws -> ProfileDTO {
        throw Unavailable()
    }
    func create(name: String, colorTag: String, avatar: String) async throws -> ProfileDTO { throw Unavailable() }
    func rename(id: String, to name: String) async throws { throw Unavailable() }
    func update(id: String, name: String, colorTag: String, avatar: String) async throws { throw Unavailable() }
    func delete(id: String) async throws { throw Unavailable() }
}

@MainActor
@Suite struct ActiveProfileStoreTests {
    @Test func loadAlwaysAsksEvenForSoloOwner() async {
        let store = ActiveProfileStore(provider: FakeRoster(), autoSelectsOwner: false)
        await store.loadAndResolve()
        #expect(store.roster.count == 1)          // owner auto-created
        #expect(store.activeProfileID == nil)     // but not auto-selected — always ask
        #expect(store.needsSelection == true)
    }

    /// Profiles switched off: never ask. Resolve to the OLDEST profile, because watch history,
    /// Continue Watching and My List are all keyed by profile id — picking any other row would
    /// silently show an empty app.
    @Test func autoSelectResolvesToTheOldestProfile() async {
        let store = ActiveProfileStore(provider: FakeRoster([
            ProfileDTO(id: "owner", name: "Me", colorTag: "gold", createdAt: Date(timeIntervalSince1970: 0)),
            ProfileDTO(id: "kid", name: "Kid", colorTag: "blue", createdAt: Date(timeIntervalSince1970: 1)),
        ]), autoSelectsOwner: true)
        await store.loadAndResolve()
        #expect(store.activeProfileID == "owner")
        #expect(store.needsSelection == false)
    }

    /// A failed profile container yields an empty roster, so there is nothing to select. The gate
    /// must STILL stay down — otherwise a broken container strands the viewer on a picker with no
    /// profiles to pick, which is the one way this could soft-lock.
    @Test func autoSelectOnAnEmptyRosterStillNeverAsks() async {
        let store = ActiveProfileStore(provider: EmptyRoster(), autoSelectsOwner: true)
        await store.loadAndResolve()
        #expect(store.roster.isEmpty)
        #expect(store.activeProfileID == nil)
        #expect(store.needsSelection == false)
    }

    @Test func selectEntersTheApp() async {
        let store = ActiveProfileStore(provider: FakeRoster(), autoSelectsOwner: false)
        await store.loadAndResolve()
        store.select("owner")
        #expect(store.activeProfileID == "owner")
        #expect(store.needsSelection == false)
    }

    @Test func switchProfileReopensTheGate() async {
        let store = ActiveProfileStore(provider: FakeRoster(), autoSelectsOwner: false)
        await store.loadAndResolve()
        store.select("owner")
        store.switchProfile()
        #expect(store.activeProfileID == nil)
        #expect(store.needsSelection == true)
    }

    @Test func createAddsToRosterWithAvatar() async {
        let store = ActiveProfileStore(provider: FakeRoster(), autoSelectsOwner: false)
        await store.loadAndResolve()
        await store.create(name: "Kid", colorTag: "blue", avatar: "🦊")
        #expect(store.roster.contains { $0.name == "Kid" && $0.avatar == "🦊" })
    }

    @Test func deleteActiveClearsSelection() async {
        let store = ActiveProfileStore(provider: FakeRoster([
            ProfileDTO(id: "owner", name: "Me", colorTag: "gold", createdAt: Date(timeIntervalSince1970: 0)),
            ProfileDTO(id: "kid", name: "Kid", colorTag: "blue", createdAt: Date(timeIntervalSince1970: 1)),
        ]), autoSelectsOwner: false)
        await store.loadAndResolve()
        store.select("kid")
        await store.delete(id: "kid")
        #expect(store.activeProfileID == nil)
        #expect(store.roster.map(\.id) == ["owner"])
    }
}
