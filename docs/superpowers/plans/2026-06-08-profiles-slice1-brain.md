# Profiles — Slice 1 (Brain Models + Stores) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure `DebridCore` foundation for multi-user profiles — `Profile` + `MyListEntry` SwiftData models and their `@ModelActor` stores (roster CRUD with cascade-delete, idempotent owner migration, My-List claim/unclaim) — all unit-tested, no UI, no CloudKit.

**Architecture:** Mirrors the existing `WatchProgressStore`/`DownloadsStore` pattern: flat `@Model` classes (every property defaulted, no unique constraint — CloudKit-ready), `@ModelActor` actors returning `Sendable` DTOs, manual dedupe. Lives in a new `Packages/DebridCore/Sources/DebridCore/Profiles/` folder. Stores filter/cascade across `Profile`, `MyListEntry`, and the existing `WatchProgress`, so test containers register all three models.

**Tech Stack:** Swift 6, SwiftData, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-06-08-profiles-design.md` (Slice 1 of 5).

**Conventions:** TDD (failing test → minimal impl → green → commit). SwiftData test suites nest under `extension SwiftDataSuite { @Suite struct … }`. Run the full `swift test --package-path Packages/DebridCore` before merging. Zero warnings.

---

## File Structure

| File | Responsibility |
|---|---|
| `Packages/DebridCore/Sources/DebridCore/Profiles/Profile.swift` (new) | `Profile` `@Model` + `ProfileDTO` Sendable snapshot |
| `Packages/DebridCore/Sources/DebridCore/Profiles/MyListEntry.swift` (new) | `MyListEntry` `@Model` (claimed title) |
| `Packages/DebridCore/Sources/DebridCore/Profiles/ProfileStore.swift` (new) | roster CRUD + cascade delete + owner migration |
| `Packages/DebridCore/Sources/DebridCore/Profiles/MyListStore.swift` (new) | claim / unclaim / list / isClaimed |
| `Packages/DebridCore/Tests/DebridCoreTests/ProfileStoreTests.swift` (new) | Profile model + store tests |
| `Packages/DebridCore/Tests/DebridCoreTests/MyListStoreTests.swift` (new) | MyListEntry + store tests |

---

## Task 1: `Profile` model + `ProfileDTO`

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Profiles/Profile.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/ProfileStoreTests.swift` (new)

- [ ] **Step 1: Write the failing test** — create the test file:

```swift
import Testing
import Foundation
import SwiftData
@testable import DebridCore

extension SwiftDataSuite {
    @Suite struct ProfileStoreTests {
        private func container() throws -> ModelContainer {
            try ModelContainer(for: Profile.self, MyListEntry.self, WatchProgress.self,
                               configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }

        @Test func profileDTOMirrorsModel() throws {
            let m = Profile(id: "p1", name: "Shahar", colorTag: "gold",
                            createdAt: Date(timeIntervalSince1970: 10))
            let dto = ProfileDTO(m)
            #expect(dto.id == "p1")
            #expect(dto.name == "Shahar")
            #expect(dto.colorTag == "gold")
            #expect(dto.createdAt == Date(timeIntervalSince1970: 10))
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter ProfileStoreTests`
Expected: FAIL — `cannot find 'Profile'` / `'ProfileDTO'` in scope.

- [ ] **Step 3: Implement the model** — create `Profile.swift`:

```swift
import Foundation
import SwiftData

/// A viewer profile on the shared Real-Debrid account (Netflix-style). CloudKit-ready: every
/// property defaulted, no unique constraint. `id` is a caller-supplied UUID string.
@Model
public final class Profile {
    public var id: String = ""
    public var name: String = ""
    /// A design-system color token (e.g. "gold"); the UI maps it to a palette. Stored as a string
    /// so the brain stays UI-free.
    public var colorTag: String = ""
    public var createdAt: Date = Date(timeIntervalSince1970: 0)

    public init(id: String = "", name: String = "", colorTag: String = "",
                createdAt: Date = Date(timeIntervalSince1970: 0)) {
        self.id = id
        self.name = name
        self.colorTag = colorTag
        self.createdAt = createdAt
    }
}

/// `Sendable` snapshot of a `Profile` — what the store hands back, so callers never touch the
/// non-`Sendable` `@Model`.
public struct ProfileDTO: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let colorTag: String
    public let createdAt: Date

    public init(id: String, name: String, colorTag: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.colorTag = colorTag
        self.createdAt = createdAt
    }

    public init(_ m: Profile) {
        self.init(id: m.id, name: m.name, colorTag: m.colorTag, createdAt: m.createdAt)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Packages/DebridCore --filter ProfileStoreTests`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Profiles/Profile.swift \
        Packages/DebridCore/Tests/DebridCoreTests/ProfileStoreTests.swift
git commit -m "feat(core): add Profile @Model + ProfileDTO"
```

---

## Task 2: `MyListEntry` model

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Profiles/MyListEntry.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/MyListStoreTests.swift` (new)

- [ ] **Step 1: Write the failing test** — create the test file:

```swift
import Testing
import Foundation
import SwiftData
@testable import DebridCore

extension SwiftDataSuite {
    @Suite struct MyListStoreTests {
        private func container() throws -> ModelContainer {
            try ModelContainer(for: Profile.self, MyListEntry.self, WatchProgress.self,
                               configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }

        @Test func entryIDIsProfileAndContentKey() {
            #expect(MyListEntry.makeID(profileID: "p1", contentKey: "movie:42") == "p1|movie:42")
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter MyListStoreTests`
Expected: FAIL — `cannot find 'MyListEntry'` in scope.

- [ ] **Step 3: Implement the model** — create `MyListEntry.swift`:

```swift
import Foundation
import SwiftData

/// A title a profile has claimed into its "My List" (by Add or Play). One row per
/// (profile, title). CloudKit-ready: defaulted properties, no unique constraint — `id` is the
/// deterministic `"<profileID>|<contentKey>"` so claims are idempotent and dedupe is explicit.
@Model
public final class MyListEntry {
    public var id: String = ""
    public var profileID: String = ""
    public var contentKey: String = ""
    public var addedAt: Date = Date(timeIntervalSince1970: 0)

    public init(id: String = "", profileID: String = "", contentKey: String = "",
                addedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.id = id
        self.profileID = profileID
        self.contentKey = contentKey
        self.addedAt = addedAt
    }

    /// The deterministic primary key for a claim.
    public static func makeID(profileID: String, contentKey: String) -> String {
        "\(profileID)|\(contentKey)"
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Packages/DebridCore --filter MyListStoreTests`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Profiles/MyListEntry.swift \
        Packages/DebridCore/Tests/DebridCoreTests/MyListStoreTests.swift
git commit -m "feat(core): add MyListEntry @Model (claimed title per profile)"
```

---

## Task 3: `ProfileStore` — create / all / rename

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Profiles/ProfileStore.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/ProfileStoreTests.swift`

- [ ] **Step 1: Write the failing tests** — append inside `ProfileStoreTests`:

```swift
        @Test func createThenAllReturnsByCreatedAtAscending() async throws {
            let store = ProfileStore(modelContainer: try container())
            _ = try await store.create(name: "B", colorTag: "blue", id: "b",
                                       at: Date(timeIntervalSince1970: 20))
            _ = try await store.create(name: "A", colorTag: "gold", id: "a",
                                       at: Date(timeIntervalSince1970: 10))
            let all = try await store.all()
            #expect(all.map(\.id) == ["a", "b"])   // oldest first
            #expect(all.first?.name == "A")
        }

        @Test func renameChangesName() async throws {
            let store = ProfileStore(modelContainer: try container())
            _ = try await store.create(name: "Old", colorTag: "gold", id: "p1",
                                       at: Date(timeIntervalSince1970: 1))
            try await store.rename(id: "p1", to: "New")
            #expect(try await store.all().first?.name == "New")
        }
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --package-path Packages/DebridCore --filter ProfileStoreTests`
Expected: FAIL — `cannot find 'ProfileStore'` in scope.

- [ ] **Step 3: Implement the store** — create `ProfileStore.swift`:

```swift
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
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter ProfileStoreTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Profiles/ProfileStore.swift \
        Packages/DebridCore/Tests/DebridCoreTests/ProfileStoreTests.swift
git commit -m "feat(core): ProfileStore create/all/rename"
```

---

## Task 4: `ProfileStore.delete` with cascade

Deleting a profile must also drop its `MyListEntry` rows and its `WatchProgress` rows (spec:
"cascade: also delete that profile's My List + progress").

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Profiles/ProfileStore.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/ProfileStoreTests.swift`

- [ ] **Step 1: Write the failing test** — append inside `ProfileStoreTests`:

```swift
        @Test func deleteCascadesMyListAndProgress() async throws {
            let c = try container()
            let store = ProfileStore(modelContainer: c)
            _ = try await store.create(name: "P1", colorTag: "gold", id: "p1",
                                       at: Date(timeIntervalSince1970: 1))
            _ = try await store.create(name: "P2", colorTag: "blue", id: "p2",
                                       at: Date(timeIntervalSince1970: 2))
            // Seed p1-owned My List + progress, and one p2 row that must survive.
            let ctx = ModelContext(c)
            ctx.insert(MyListEntry(id: "p1|m", profileID: "p1", contentKey: "m"))
            ctx.insert(WatchProgress(contentKey: "m", profileID: "p1"))
            ctx.insert(WatchProgress(contentKey: "n", profileID: "p2"))
            try ctx.save()

            try await store.delete(id: "p1")

            #expect(try await store.all().map(\.id) == ["p2"])
            let ctx2 = ModelContext(c)
            #expect(try ctx2.fetch(FetchDescriptor<MyListEntry>()).isEmpty)
            let progress = try ctx2.fetch(FetchDescriptor<WatchProgress>())
            #expect(progress.map(\.profileID) == ["p2"])   // p1's progress gone, p2's kept
        }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter ProfileStoreTests`
Expected: FAIL — `value of type 'ProfileStore' has no member 'delete'`.

- [ ] **Step 3: Implement cascade delete** — add to `ProfileStore`:

```swift
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Packages/DebridCore --filter ProfileStoreTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Profiles/ProfileStore.swift \
        Packages/DebridCore/Tests/DebridCoreTests/ProfileStoreTests.swift
git commit -m "feat(core): ProfileStore.delete cascades My List + progress"
```

---

## Task 5: `ProfileStore.ensureOwnerProfileAndMigrate`

On first launch (no profiles), create an owner profile and assign every `profileID == nil`
`WatchProgress` row to it. Idempotent: a no-op once any profile exists.

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Profiles/ProfileStore.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/ProfileStoreTests.swift`

- [ ] **Step 1: Write the failing tests** — append inside `ProfileStoreTests`:

```swift
        @Test func ensureOwnerCreatesProfileAndMigratesNilProgress() async throws {
            let c = try container()
            let store = ProfileStore(modelContainer: c)
            let ctx = ModelContext(c)
            ctx.insert(WatchProgress(contentKey: "old", positionSeconds: 5))   // profileID nil
            try ctx.save()

            let owner = try await store.ensureOwnerProfileAndMigrate(
                ownerName: "Me", colorTag: "gold", id: "owner", at: Date(timeIntervalSince1970: 1))

            #expect(owner.id == "owner")
            #expect(try await store.all().map(\.id) == ["owner"])
            let migrated = try ModelContext(c).fetch(FetchDescriptor<WatchProgress>())
            #expect(migrated.first?.profileID == "owner")   // nil row re-keyed to owner
        }

        @Test func ensureOwnerIsIdempotentWhenProfilesExist() async throws {
            let store = ProfileStore(modelContainer: try container())
            _ = try await store.create(name: "Existing", colorTag: "blue", id: "p1",
                                       at: Date(timeIntervalSince1970: 1))
            let owner = try await store.ensureOwnerProfileAndMigrate(
                ownerName: "Me", colorTag: "gold", id: "owner", at: Date(timeIntervalSince1970: 2))
            #expect(owner.id == "p1")                       // returns the existing earliest profile
            #expect(try await store.all().map(\.id) == ["p1"])   // no second profile created
        }
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --package-path Packages/DebridCore --filter ProfileStoreTests`
Expected: FAIL — `no member 'ensureOwnerProfileAndMigrate'`.

- [ ] **Step 3: Implement** — add to `ProfileStore`:

```swift
    /// Idempotent first-launch migration: if any profile exists, return the earliest (the owner)
    /// untouched. Otherwise create an owner profile and re-key every `profileID == nil`
    /// `WatchProgress` row to it, so Phase-1 progress is preserved under the new profile model.
    @discardableResult
    public func ensureOwnerProfileAndMigrate(ownerName: String, colorTag: String,
                                             id: String = UUID().uuidString,
                                             at: Date = Date()) throws -> ProfileDTO {
        let existing = try modelContext.fetch(FetchDescriptor<Profile>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]))
        if let owner = existing.first { return ProfileDTO(owner) }

        let owner = Profile(id: id, name: ownerName, colorTag: colorTag, createdAt: at)
        modelContext.insert(owner)
        for row in try modelContext.fetch(FetchDescriptor<WatchProgress>(
            predicate: #Predicate { $0.profileID == nil })) {
            row.profileID = id
        }
        try modelContext.save()
        return ProfileDTO(owner)
    }
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter ProfileStoreTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Profiles/ProfileStore.swift \
        Packages/DebridCore/Tests/DebridCoreTests/ProfileStoreTests.swift
git commit -m "feat(core): ProfileStore owner-profile bootstrap + nil-progress migration"
```

---

## Task 6: `MyListStore` — claim / unclaim / isClaimed / contentKeys

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Profiles/MyListStore.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/MyListStoreTests.swift`

- [ ] **Step 1: Write the failing tests** — append inside `MyListStoreTests`:

```swift
        @Test func claimIsIdempotentAndQueryable() async throws {
            let store = MyListStore(modelContainer: try container())
            try await store.claim(profileID: "p1", contentKey: "m", at: Date(timeIntervalSince1970: 1))
            try await store.claim(profileID: "p1", contentKey: "m", at: Date(timeIntervalSince1970: 2))
            #expect(try await store.isClaimed(profileID: "p1", contentKey: "m"))
            #expect(try await store.contentKeys(forProfile: "p1") == ["m"])   // not duplicated
        }

        @Test func unclaimRemovesOnlyThatProfilesEntry() async throws {
            let store = MyListStore(modelContainer: try container())
            try await store.claim(profileID: "p1", contentKey: "m", at: Date(timeIntervalSince1970: 1))
            try await store.claim(profileID: "p2", contentKey: "m", at: Date(timeIntervalSince1970: 1))
            try await store.unclaim(profileID: "p1", contentKey: "m")
            #expect(try await store.isClaimed(profileID: "p1", contentKey: "m") == false)
            #expect(try await store.isClaimed(profileID: "p2", contentKey: "m") == true)
        }

        @Test func contentKeysAreNewestFirstDeduped() async throws {
            let c = try container()
            let store = MyListStore(modelContainer: c)
            // Seed a CloudKit-style duplicate (same id) directly, then a newer distinct claim.
            let ctx = ModelContext(c)
            ctx.insert(MyListEntry(id: "p1|a", profileID: "p1", contentKey: "a",
                                   addedAt: Date(timeIntervalSince1970: 1)))
            ctx.insert(MyListEntry(id: "p1|a", profileID: "p1", contentKey: "a",
                                   addedAt: Date(timeIntervalSince1970: 1)))
            try ctx.save()
            try await store.claim(profileID: "p1", contentKey: "b", at: Date(timeIntervalSince1970: 9))
            #expect(try await store.contentKeys(forProfile: "p1") == ["b", "a"])   // newest first, "a" once
        }
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --package-path Packages/DebridCore --filter MyListStoreTests`
Expected: FAIL — `cannot find 'MyListStore'` in scope.

- [ ] **Step 3: Implement** — create `MyListStore.swift`:

```swift
import Foundation
import SwiftData

/// SwiftData-backed per-profile "My List" of claimed titles. `@ModelActor` isolates its context.
/// Claims are keyed by the deterministic `MyListEntry.id`, so claiming is an idempotent upsert and
/// CloudKit-merged duplicates are reconciled on read (keep one, newest `addedAt`).
@ModelActor
public actor MyListStore {
    /// Claim a title for a profile (upsert by deterministic id; refreshes `addedAt`).
    public func claim(profileID: String, contentKey: String, at: Date = Date()) throws {
        let id = MyListEntry.makeID(profileID: profileID, contentKey: contentKey)
        let row = try fetchOne(id: id) ?? {
            let e = MyListEntry(id: id, profileID: profileID, contentKey: contentKey)
            modelContext.insert(e)
            return e
        }()
        row.addedAt = at
        try modelContext.save()
    }

    public func unclaim(profileID: String, contentKey: String) throws {
        let id = MyListEntry.makeID(profileID: profileID, contentKey: contentKey)
        for row in try modelContext.fetch(FetchDescriptor<MyListEntry>(
            predicate: #Predicate { $0.id == id })) {
            modelContext.delete(row)
        }
        try modelContext.save()
    }

    public func isClaimed(profileID: String, contentKey: String) throws -> Bool {
        let id = MyListEntry.makeID(profileID: profileID, contentKey: contentKey)
        return try fetchOne(id: id) != nil
    }

    /// Claimed content keys for a profile, newest first, deduped by content key.
    public func contentKeys(forProfile profileID: String) throws -> [String] {
        let rows = try modelContext.fetch(FetchDescriptor<MyListEntry>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]))
        var seen = Set<String>()
        return rows.compactMap { seen.insert($0.contentKey).inserted ? $0.contentKey : nil }
    }

    /// Newest row for an id; if CloudKit merged duplicates, keep the newest and delete the rest.
    private func fetchOne(id: String) throws -> MyListEntry? {
        let matches = try modelContext.fetch(FetchDescriptor<MyListEntry>(
            predicate: #Predicate { $0.id == id },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]))
        guard let survivor = matches.first else { return nil }
        if matches.count > 1 {
            for stale in matches.dropFirst() { modelContext.delete(stale) }
            try modelContext.save()
        }
        return survivor
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter MyListStoreTests`
Expected: PASS (4 tests in this suite).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Profiles/MyListStore.swift \
        Packages/DebridCore/Tests/DebridCoreTests/MyListStoreTests.swift
git commit -m "feat(core): MyListStore claim/unclaim/isClaimed/contentKeys (dedupe on read)"
```

---

## Task 7: Full green sweep

**Files:** none (verification only)

- [ ] **Step 1: Run the full DebridCore suite + warning check**

Run:
```bash
swift test --package-path Packages/DebridCore 2>&1 | tail -3
swift build --package-path Packages/DebridCore 2>&1 | grep -i warning || echo "(no warnings)"
```
Expected: all suites green (256 prior + the new Profile/MyList tests), no warnings. The existing
`WatchProgress` suites still pass (this slice doesn't change `WatchProgress` behavior — only adds a
container that registers it alongside the new models).

---

## Notes for the implementer

- This slice is **brain-only**: no `AppSession`, no UI, no CloudKit config. Slice 3 wires these
  stores into `AppSession`'s CloudKit container (its schema must then list `Profile`,
  `MyListEntry`, `WatchProgress` together) and injects the active profile.
- `WatchProgress` already has `profileID` (added in Phase 1). This slice reads/writes it via the
  cascade + migration but does **not** yet change `WatchProgressStore`'s own methods — that's
  Slice 2 (per-profile scoping).
- Keep `DebridCore` CloudKit-free and `swift test`-able on the dev Mac.
- New SwiftData suites **must** nest under `extension SwiftDataSuite { @Suite struct … }`.
