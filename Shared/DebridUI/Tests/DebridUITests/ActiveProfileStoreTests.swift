import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// In-memory roster fake. `actor` for Sendable conformance.
private actor FakeRoster: ProfileRosterProviding {
    private var rows: [ProfileDTO]
    init(_ rows: [ProfileDTO] = []) { self.rows = rows }
    func all() async throws -> [ProfileDTO] { rows.sorted { $0.createdAt < $1.createdAt } }
    func ensureOwnerProfileAndMigrate(ownerName: String, colorTag: String) async throws -> ProfileDTO {
        if let owner = rows.sorted(by: { $0.createdAt < $1.createdAt }).first { return owner }
        let owner = ProfileDTO(id: "owner", name: ownerName, colorTag: colorTag,
                               createdAt: Date(timeIntervalSince1970: 0))
        rows.append(owner)
        return owner
    }
    func create(name: String, colorTag: String) async throws -> ProfileDTO {
        let p = ProfileDTO(id: "id\(rows.count)", name: name, colorTag: colorTag,
                           createdAt: Date(timeIntervalSince1970: Double(rows.count + 1)))
        rows.append(p); return p
    }
    func rename(id: String, to name: String) async throws {
        if let i = rows.firstIndex(where: { $0.id == id }) {
            rows[i] = ProfileDTO(id: id, name: name, colorTag: rows[i].colorTag, createdAt: rows[i].createdAt)
        }
    }
    func delete(id: String) async throws { rows.removeAll { $0.id == id } }
}

/// Fresh, isolated UserDefaults per test.
private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "test.\(UUID().uuidString)")!
}

@MainActor
@Suite struct ActiveProfileStoreTests {
    @Test func soloOwnerAutoSelectsAndNoSelectionNeeded() async {
        let store = ActiveProfileStore(provider: FakeRoster(), defaults: freshDefaults())
        await store.loadAndResolve()
        #expect(store.roster.count == 1)
        #expect(store.activeProfileID == "owner")
        #expect(store.needsSelection == false)
    }

    private func twoProfiles() -> FakeRoster {
        FakeRoster([
            ProfileDTO(id: "owner", name: "Me", colorTag: "gold", createdAt: Date(timeIntervalSince1970: 0)),
            ProfileDTO(id: "kid", name: "Kid", colorTag: "blue", createdAt: Date(timeIntervalSince1970: 1)),
        ])
    }

    @Test func multipleProfilesWithNoStoredSelectionNeedsSelection() async {
        let store = ActiveProfileStore(provider: twoProfiles(), defaults: freshDefaults())
        await store.loadAndResolve()
        #expect(store.roster.count == 2)
        #expect(store.activeProfileID == nil)
        #expect(store.needsSelection == true)
    }

    @Test func selectPersistsAndResolvesNextLaunch() async {
        let d = freshDefaults()
        let s1 = ActiveProfileStore(provider: twoProfiles(), defaults: d)
        await s1.loadAndResolve()
        s1.select("kid")
        #expect(s1.activeProfileID == "kid")
        #expect(s1.needsSelection == false)
        // New instance, same defaults → resolves the stored selection, no gate.
        let s2 = ActiveProfileStore(provider: twoProfiles(), defaults: d)
        await s2.loadAndResolve()
        #expect(s2.activeProfileID == "kid")
        #expect(s2.needsSelection == false)
    }

    @Test func staleStoredSelectionFallsBackToGate() async {
        let d = freshDefaults()
        d.set("ghost", forKey: "seret.activeProfileID")   // not in roster
        let store = ActiveProfileStore(provider: twoProfiles(), defaults: d)
        await store.loadAndResolve()
        #expect(store.activeProfileID == nil)
        #expect(store.needsSelection == true)
    }

    @Test func deleteActiveClearsSelection() async {
        let store = ActiveProfileStore(provider: twoProfiles(), defaults: freshDefaults())
        await store.loadAndResolve()
        store.select("kid")
        await store.delete(id: "kid")
        #expect(store.activeProfileID == nil)
        #expect(store.roster.map(\.id) == ["owner"])
    }

    @Test func createAddsToRoster() async {
        let store = ActiveProfileStore(provider: FakeRoster(), defaults: freshDefaults())
        await store.loadAndResolve()
        await store.create(name: "Guest", colorTag: "blue")
        #expect(store.roster.contains { $0.name == "Guest" })
    }
}
