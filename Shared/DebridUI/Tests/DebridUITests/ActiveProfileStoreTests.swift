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

@MainActor
@Suite struct ActiveProfileStoreTests {
    @Test func loadAlwaysAsksEvenForSoloOwner() async {
        let store = ActiveProfileStore(provider: FakeRoster())
        await store.loadAndResolve()
        #expect(store.roster.count == 1)          // owner auto-created
        #expect(store.activeProfileID == nil)     // but not auto-selected — always ask
        #expect(store.needsSelection == true)
    }

    @Test func selectEntersTheApp() async {
        let store = ActiveProfileStore(provider: FakeRoster())
        await store.loadAndResolve()
        store.select("owner")
        #expect(store.activeProfileID == "owner")
        #expect(store.needsSelection == false)
    }

    @Test func switchProfileReopensTheGate() async {
        let store = ActiveProfileStore(provider: FakeRoster())
        await store.loadAndResolve()
        store.select("owner")
        store.switchProfile()
        #expect(store.activeProfileID == nil)
        #expect(store.needsSelection == true)
    }

    @Test func createAddsToRosterWithAvatar() async {
        let store = ActiveProfileStore(provider: FakeRoster())
        await store.loadAndResolve()
        await store.create(name: "Kid", colorTag: "blue", avatar: "🦊")
        #expect(store.roster.contains { $0.name == "Kid" && $0.avatar == "🦊" })
    }

    @Test func deleteActiveClearsSelection() async {
        let store = ActiveProfileStore(provider: FakeRoster([
            ProfileDTO(id: "owner", name: "Me", colorTag: "gold", createdAt: Date(timeIntervalSince1970: 0)),
            ProfileDTO(id: "kid", name: "Kid", colorTag: "blue", createdAt: Date(timeIntervalSince1970: 1)),
        ]))
        await store.loadAndResolve()
        store.select("kid")
        await store.delete(id: "kid")
        #expect(store.activeProfileID == nil)
        #expect(store.roster.map(\.id) == ["owner"])
    }
}
