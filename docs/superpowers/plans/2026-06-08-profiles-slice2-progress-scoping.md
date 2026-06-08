# Profiles — Slice 2 (Per-Profile Watch Progress + Active Owner Profile) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scope all watch progress (resume + Continue Watching) to a profile, and wire a single auto-created **owner profile** as the active profile, so the existing single user keeps working unchanged while the data is now per-profile.

**Architecture:** `WatchProgressStore`, its seam, and `PlaybackCoordinator` gain a `profileID`; reads filter on it and the duplicate-reconcile key becomes (contentKey, profileID). `AppSession` builds `WatchProgressStore`, `ProfileStore`, and `MyListStore` from **one shared CloudKit `ModelContainer`** (schema = all three models), bootstraps an owner profile on sign-in (`ensureOwnerProfileAndMigrate`), exposes `activeProfileID`, and injects it into Home/Detail/playback. Profile *switching* UI and My List are later slices.

**Tech Stack:** Swift 6, SwiftData (+ CloudKit), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-06-08-profiles-design.md` (Slices 2+3 of the spec, merged because per-profile reads only work with a real active profile id). Builds on Slice 1 (`ProfileStore`/`MyListStore` exist).

**Conventions:** TDD for brain/seam (package `swift test`); AppSession + app-view wiring is build-verified (repo pattern — the simulator/CloudKit can't be unit-tested here). SwiftData suites nest under `SwiftDataSuite`. Zero warnings. Full `swift test` before merge.

---

## File Structure

| File | Change |
|---|---|
| `Packages/DebridCore/Sources/DebridCore/Persistence/WatchProgressStore.swift` | `profileID` on `record`/`progress`/`recentlyWatched`; reconcile per (key, profileID) |
| `Packages/DebridCore/Sources/DebridCore/Playback/PlaybackCoordinator.swift` | hold `profileID`; pass to store |
| `Packages/DebridCore/Tests/DebridCoreTests/WatchProgressReconcileTests.swift` | per-profile isolation tests |
| `Packages/DebridCore/Tests/DebridCoreTests/PlaybackCoordinatorTests.swift` | coordinator passes profileID (new or extend) |
| `Shared/DebridUI/Sources/DebridUI/Detail/WatchProgressProviding.swift` | seam methods gain `profileID` |
| `Shared/DebridUI/Sources/DebridUI/Home/HomeStore.swift` | `activeProfileID` + scoped `recentlyWatched` |
| `Shared/DebridUI/Sources/DebridUI/Detail/DetailStore.swift` | `profileID` + scoped `record`/`progress` |
| `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift` | shared 3-model container; build Profile/MyList stores; owner bootstrap; `activeProfileID`; inject |
| `Apps/SeretTV/Detail/DetailView.swift`, `Apps/SeretMobile/Detail/DetailScreen.swift` | pass `session.activeProfileID` into `DetailStore` |

---

## Task 1: `WatchProgressStore` — scope by `profileID`

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Persistence/WatchProgressStore.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/WatchProgressReconcileTests.swift`

- [ ] **Step 1: Write the failing tests** — append inside `WatchProgressReconcileTests`:

```swift
        @Test func progressIsIsolatedPerProfile() async throws {
            let s = WatchProgressStore(modelContainer: try container())
            try await s.record(contentKey: "m", sourceKey: "x", positionSeconds: 10,
                               durationSeconds: 100, finished: false, profileID: "p1")
            try await s.record(contentKey: "m", sourceKey: "x", positionSeconds: 80,
                               durationSeconds: 100, finished: false, profileID: "p2")
            #expect(try await s.progress(forContentKey: "m", profileID: "p1")?.positionSeconds == 10)
            #expect(try await s.progress(forContentKey: "m", profileID: "p2")?.positionSeconds == 80)
            #expect(try await s.allCount() == 2)   // one row per (key, profile), not upserted together
        }

        @Test func recentlyWatchedIsScopedToProfile() async throws {
            let s = WatchProgressStore(modelContainer: try container())
            try await s.record(contentKey: "a", sourceKey: "x", positionSeconds: 10,
                               durationSeconds: 100, finished: false, profileID: "p1")
            try await s.record(contentKey: "b", sourceKey: "x", positionSeconds: 20,
                               durationSeconds: 100, finished: false, profileID: "p2")
            let p1 = try await s.recentlyWatched(limit: 20, profileID: "p1")
            #expect(p1.map(\.contentKey) == ["a"])   // p2's "b" excluded
        }
```

Add the `container()` helper to this suite if not present (it currently builds inline containers):

```swift
        private func container() throws -> ModelContainer {
            try ModelContainer(for: WatchProgress.self,
                               configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --package-path Packages/DebridCore --filter WatchProgressReconcileTests`
Expected: FAIL — `record`/`progress`/`recentlyWatched` have no `profileID:` argument.

- [ ] **Step 3: Add `profileID` to the store** — in `WatchProgressStore.swift`, update the three public methods and `fetchOne` to be profile-scoped:

```swift
    public func progress(forContentKey key: String, profileID: String) throws -> WatchState? {
        try fetchOne(contentKey: key, profileID: profileID).map(WatchState.init)
    }

    public func record(contentKey: String, sourceKey: String,
                       positionSeconds: Double, durationSeconds: Double,
                       finished: Bool, profileID: String, at: Date = Date()) throws {
        let row = try fetchOne(contentKey: contentKey, profileID: profileID) ?? {
            let r = WatchProgress(contentKey: contentKey, profileID: profileID)
            modelContext.insert(r)
            return r
        }()
        row.sourceKey = sourceKey
        row.positionSeconds = positionSeconds
        row.durationSeconds = durationSeconds
        row.finished = finished
        row.profileID = profileID
        row.updatedAt = at
        try modelContext.save()
    }

    public func recentlyWatched(limit: Int, profileID: String) throws -> [WatchState] {
        guard limit > 0 else { return [] }
        let rows = try modelContext.fetch(FetchDescriptor<WatchProgress>(
            predicate: #Predicate { $0.finished == false && $0.positionSeconds > 0
                                    && $0.profileID == profileID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
        var seen = Set<String>()
        var out: [WatchState] = []
        for row in rows where seen.insert(row.contentKey).inserted {
            out.append(WatchState(row))
            if out.count == limit { break }
        }
        return out
    }
```

And replace `fetchOne` so the reconcile key is (contentKey, profileID):

```swift
    /// Newest row for (key, profile). Reconcile CloudKit duplicates: keep newest `updatedAt`,
    /// delete the rest (last-write-wins).
    private func fetchOne(contentKey key: String, profileID: String) throws -> WatchProgress? {
        let matches = try modelContext.fetch(FetchDescriptor<WatchProgress>(
            predicate: #Predicate { $0.contentKey == key && $0.profileID == profileID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
        guard let survivor = matches.first else { return nil }
        if matches.count > 1 {
            for stale in matches.dropFirst() { modelContext.delete(stale) }
            try modelContext.save()
        }
        return survivor
    }
```

> `deleteProgress(forContentKeys:)` stays profile-agnostic (removing a title from the shared
> library clears it for everyone) — do not change it.

- [ ] **Step 4: Update the Phase-1 reconcile tests for the new signatures** — the existing
  `progressReturnsNewestAndPrunesDuplicates` and `recentlyWatchedDedupesByContentKey` call the old
  signatures. Update their seed + calls to pass `profileID: "p1"` on the seeded rows and the reads:

```swift
        private func seedDuplicates(_ c: ModelContainer) throws {
            let ctx = ModelContext(c)
            ctx.insert(WatchProgress(contentKey: "dupe", sourceKey: "old", positionSeconds: 10,
                                     durationSeconds: 100, finished: false,
                                     updatedAt: Date(timeIntervalSince1970: 1), profileID: "p1"))
            ctx.insert(WatchProgress(contentKey: "dupe", sourceKey: "new", positionSeconds: 80,
                                     durationSeconds: 100, finished: false,
                                     updatedAt: Date(timeIntervalSince1970: 5), profileID: "p1"))
            try ctx.save()
        }
```

In `progressReturnsNewestAndPrunesDuplicates`: `try await store.progress(forContentKey: "dupe", profileID: "p1")`.
In `recentlyWatchedDedupesByContentKey`: `try await store.recentlyWatched(limit: 20, profileID: "p1")`.

- [ ] **Step 5: Run to verify all pass**

Run: `swift test --package-path Packages/DebridCore --filter WatchProgressReconcileTests`
Expected: PASS (existing reconcile tests + 2 new isolation tests).

- [ ] **Step 6: Update the other existing WatchProgress suites** — `WatchProgressStoreTests` and
  `WatchProgressDeleteTests` call the old signatures and will now fail to compile. Add
  `profileID: "p1"` (any fixed id) to every `record(...)` call and every `progress(forContentKey:)`
  call in both files (the `deleteProgress` / `allCount` calls are unchanged). Run:

Run: `swift test --package-path Packages/DebridCore --filter WatchProgress`
Expected: PASS (all three WatchProgress suites green).

- [ ] **Step 7: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Persistence/WatchProgressStore.swift \
        Packages/DebridCore/Tests/DebridCoreTests/WatchProgress*.swift
git commit -m "feat(core): scope WatchProgressStore by profileID (reconcile per key+profile)"
```

---

## Task 2: `WatchProgressProviding` seam — add `profileID`

**Files:**
- Modify: `Shared/DebridUI/Sources/DebridUI/Detail/WatchProgressProviding.swift`

- [ ] **Step 1: Update the protocol + the store witness** — replace the protocol body and the
  `record` overload so the seam mirrors the store:

```swift
public protocol WatchProgressProviding: Sendable {
    func progress(forContentKey key: String, profileID: String) async throws -> WatchState?
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws
    /// Continue-Watching feed for one profile: unfinished rows with progress, newest first.
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState]
    /// Delete progress rows for the given content keys across all profiles (item removed from the
    /// shared library).
    func deleteProgress(forContentKeys keys: [String]) async throws
}

extension WatchProgressStore: WatchProgressProviding {
    // `progress(forContentKey:profileID:)` and `recentlyWatched(limit:profileID:)` satisfy the
    // requirements directly. Provide the no-`at:` `record` overload the seam declares.
    public func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                       durationSeconds: Double, finished: Bool, profileID: String) throws {
        try record(contentKey: contentKey, sourceKey: sourceKey, positionSeconds: positionSeconds,
                   durationSeconds: durationSeconds, finished: finished, profileID: profileID,
                   at: Date())
    }
}
```

- [ ] **Step 2: Build** (callers updated in Tasks 4–5; expect known errors at HomeStore/DetailStore until then)

Run: `swift build --package-path Shared/DebridUI 2>&1 | grep -c error:`
Expected: a small number of errors only at `HomeStore.swift` / `DetailStore.swift` call sites (fixed next). Note them; do not commit yet — Task 5 commits the seam + both callers together so the package never commits broken.

---

## Task 3: `PlaybackCoordinator` — carry `profileID`

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Playback/PlaybackCoordinator.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/PlaybackCoordinatorTests.swift`

- [ ] **Step 1: Write the failing test** — append (or create the suite under `SwiftDataSuite`):

```swift
        @Test func coordinatorRecordsAndResumesUnderItsProfile() async throws {
            let store = WatchProgressStore(modelContainer: try ModelContainer(
                for: WatchProgress.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
            let p1 = PlaybackCoordinator(store: store, profileID: "p1")
            let p2 = PlaybackCoordinator(store: store, profileID: "p2")
            await p1.record(contentKey: "m", sourceKey: "x", position: 30, duration: 100)
            #expect(await p1.resumePosition(contentKey: "m") == 30)
            #expect(await p2.resumePosition(contentKey: "m") == 0)   // p2 has no progress for "m"
        }
```

(If `PlaybackCoordinatorTests.swift` already exists, add the test to it and update any existing
tests to pass `profileID:` into the coordinator init and `record:`.)

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter PlaybackCoordinator`
Expected: FAIL — `PlaybackCoordinator.init` has no `profileID:` argument.

- [ ] **Step 3: Implement** — in `PlaybackCoordinator.swift`, add the stored `profileID` and thread it:

```swift
public struct PlaybackCoordinator: Sendable {
    private let store: WatchProgressStore
    private let finishedThreshold: Double
    private let profileID: String

    public init(store: WatchProgressStore, profileID: String, finishedThreshold: Double = 0.95) {
        self.store = store
        self.profileID = profileID
        self.finishedThreshold = finishedThreshold
    }

    public func resumePosition(contentKey: String) async -> Double {
        guard let state = (try? await store.progress(forContentKey: contentKey,
                                                     profileID: profileID)) ?? nil,
              !state.finished else { return 0 }
        return state.positionSeconds
    }

    public func record(contentKey: String, sourceKey: String,
                       position: Double, duration: Double) async {
        let finished = duration > 0 && position / duration >= finishedThreshold
        try? await store.record(contentKey: contentKey, sourceKey: sourceKey,
                                positionSeconds: position, durationSeconds: duration,
                                finished: finished, profileID: profileID)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Packages/DebridCore --filter PlaybackCoordinator`
Expected: PASS.

- [ ] **Step 5: Full DebridCore sweep + commit**

Run: `swift test --package-path Packages/DebridCore 2>&1 | tail -2` (all green)
Run: `swift build --package-path Packages/DebridCore 2>&1 | grep -i warning || echo none` (none)

```bash
git add Packages/DebridCore/Sources/DebridCore/Playback/PlaybackCoordinator.swift \
        Packages/DebridCore/Tests/DebridCoreTests/PlaybackCoordinatorTests.swift
git commit -m "feat(core): PlaybackCoordinator carries profileID for per-profile resume/record"
```

---

## Task 4: `HomeStore` — scope Continue Watching to the active profile

**Files:**
- Modify: `Shared/DebridUI/Sources/DebridUI/Home/HomeStore.swift`
- Test: `Shared/DebridUI/Tests/DebridUITests/HomeStoreTests.swift`

- [ ] **Step 1: Update the test** — `HomeStoreTests` uses a fake `WatchProgressProviding`. Update
  the fake to the new seam signatures and assert scoping. Find the fake's `recentlyWatched` and
  change it to `recentlyWatched(limit:profileID:)`; add a stored `activeProfileID` expectation:

```swift
        @Test func rebuildRequestsTheActiveProfilesProgress() async throws {
            let watch = FakeWatch(recent: ["p1": [WatchState(contentKey: "a", sourceKey: "x",
                positionSeconds: 10, durationSeconds: 100, finished: false,
                updatedAt: Date(timeIntervalSince1970: 1))]])
            let home = HomeStore(watch: watch)
            home.activeProfileID = "p1"
            await home.rebuild(movies: [TestData.movie(id: "a")], shows: [])
            #expect(home.continueWatching.map(\.item.id) == ["a"])
        }
```

(Adapt `FakeWatch` and `TestData.movie` to the existing test helpers in that file — the fake now
keys its canned `recentlyWatched` results by `profileID` and records which id it was asked for.)

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Shared/DebridUI --filter HomeStoreTests`
Expected: FAIL — `HomeStore` has no `activeProfileID`; seam signature mismatch.

- [ ] **Step 3: Implement** — in `HomeStore.swift`, add `activeProfileID` and use it:

```swift
    public var activeProfileID: String?

    /// Recompute both rails for the active profile from the current library + watch progress.
    public func rebuild(movies: [MediaItem], shows: [MediaItem]) async {
        guard let profileID = activeProfileID else { continueWatching = []; recentlyAdded = []; return }
        let states = (try? await watch.recentlyWatched(limit: 20, profileID: profileID)) ?? []
        continueWatching = states.compactMap { Self.resolve($0, movies: movies, shows: shows) }
        let all = movies + shows
        recentlyAdded = Array(all.filter { $0.addedAt != nil }
            .sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
            .prefix(20))
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Shared/DebridUI --filter HomeStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit** (with Task 5 — the seam + both callers land together; see Task 5 Step 5).

---

## Task 5: `DetailStore` — scope progress to the active profile, then commit the DebridUI change set

**Files:**
- Modify: `Shared/DebridUI/Sources/DebridUI/Detail/DetailStore.swift`
- Test: `Shared/DebridUI/Tests/DebridUITests/DetailStoreTests.swift`

- [ ] **Step 1: Update the test** — `DetailStoreTests` constructs `DetailStore` and a fake watch.
  Add a `profileID` to the init and assert record/progress use it. Update the fake to the new seam.
  Add `profileID: "p1"` to the `DetailStore(item:details:watch:...)` call(s) and assert a recorded
  mark is read back for `"p1"`:

```swift
        @Test func markWatchedRecordsUnderTheProfile() async throws {
            let watch = FakeWatch()
            let store = DetailStore(item: TestData.movie(id: "m"), details: FakeDetails(),
                                    watch: watch, profileID: "p1")
            await store.markWatched(/* existing args */)
            #expect(watch.recorded.contains { $0.contentKey == "m" && $0.profileID == "p1" })
        }
```

(Adapt to the existing `DetailStoreTests` helpers/fakes and the real `markWatched` signature.)

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Shared/DebridUI --filter DetailStoreTests`
Expected: FAIL — `DetailStore.init` has no `profileID:`.

- [ ] **Step 3: Implement** — in `DetailStore.swift`:
  - Add `private let profileID: String?` and a `profileID: String? = nil` parameter to `init`,
    assigning `self.profileID = profileID`.
  - At the `watch.record(...)` call (~line 148) add `profileID: profileID ?? ""`.
  - At the `watch.progress(forContentKey: key)` call (~line 219) change to
    `watch.progress(forContentKey: key, profileID: profileID ?? "")`.
  - Guard both: if `profileID == nil`, skip (no active profile yet). E.g. wrap the existing
    `guard let watch else { return }` as `guard let watch, let profileID else { return }` and use
    `profileID` directly.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Shared/DebridUI --filter DetailStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit the seam + HomeStore + DetailStore together** (so the package never commits broken)

Run: `swift test --package-path Shared/DebridUI 2>&1 | tail -2` (all green)
Run: `swift build --package-path Shared/DebridUI 2>&1 | grep -i warning || echo none` (none)

```bash
git add Shared/DebridUI/Sources/DebridUI/Detail/WatchProgressProviding.swift \
        Shared/DebridUI/Sources/DebridUI/Home/HomeStore.swift \
        Shared/DebridUI/Sources/DebridUI/Detail/DetailStore.swift \
        Shared/DebridUI/Tests/DebridUITests/HomeStoreTests.swift \
        Shared/DebridUI/Tests/DebridUITests/DetailStoreTests.swift
git commit -m "feat(ui): scope Home + Detail watch progress to the active profile (seam gains profileID)"
```

---

## Task 6: `AppSession` — shared 3-model container + Profile/MyList stores

**Files:**
- Modify: `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift`

- [ ] **Step 1: Replace `makeWatchProgressStore` with a shared-container factory** — it must build
  one container holding all three models and return all three stores so cascade/migration work and
  they share one CloudKit DB:

```swift
    /// All profile-related stores, built from ONE container so cascade-delete + migration work and
    /// they share a single CloudKit private DB. Falls back to local-only without iCloud.
    private struct ProfileStores {
        let watch: WatchProgressStore
        let profiles: ProfileStore
        let myList: MyListStore
    }

    private static func makeProfileStores() -> ProfileStores? {
        let schema = Schema([WatchProgress.self, Profile.self, MyListEntry.self])
        let cloud = ModelConfiguration(schema: schema,
                                       cloudKitDatabase: .private(cloudKitContainerID))
        let container = (try? ModelContainer(for: schema, configurations: cloud))
            ?? (try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema)))
        guard let container else { return nil }
        return ProfileStores(watch: WatchProgressStore(modelContainer: container),
                             profiles: ProfileStore(modelContainer: container),
                             myList: MyListStore(modelContainer: container))
    }
```

- [ ] **Step 2: Add the new stored properties** — near `watchProgressStore`:

```swift
    public private(set) var profileStore: ProfileStore?
    public private(set) var myListStore: MyListStore?
    /// The profile this device is currently watching as. Set after owner bootstrap / profile switch.
    public private(set) var activeProfileID: String?
```

- [ ] **Step 3: Use the factory in `enterSignedIn()`** — replace:

```swift
        let concreteStore = Self.makeWatchProgressStore()
        watchProgressStore = concreteStore
        watchStore = concreteStore.map { $0 as WatchProgressProviding }
```

with:

```swift
        let stores = Self.makeProfileStores()
        watchProgressStore = stores?.watch
        watchStore = stores?.watch.map { $0 as WatchProgressProviding }   // (see note)
        profileStore = stores?.profiles
        myListStore = stores?.myList
```

> Note: `stores?.watch` is non-optional inside the struct; write
> `watchStore = stores.map { $0.watch as WatchProgressProviding }` and
> `watchProgressStore = stores?.watch`. Keep the existing `watchStore`/`watchProgressStore`
> property types unchanged.

- [ ] **Step 4: Build** (owner bootstrap injected next task)

Run: `swift build --package-path Shared/DebridUI 2>&1 | grep -i warning || echo none`
Expected: builds (warnings none). The old `makeWatchProgressStore` is now unused — delete it.

- [ ] **Step 5: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift
git commit -m "feat(ui): build WatchProgress/Profile/MyList stores from one shared CloudKit container"
```

---

## Task 7: `AppSession` — owner bootstrap + inject active profile

**Files:**
- Modify: `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift`

- [ ] **Step 1: Bootstrap the owner on sign-in** — at the end of `enterSignedIn()` (after `home` is
  composed and the remote-change observer is installed), kick off the owner bootstrap and wire the
  active profile into Home:

```swift
        // Profiles: ensure an owner profile exists (migrating Phase-1 progress), set it active on
        // this device, and scope Home to it. Profile switching arrives in a later slice.
        if let profileStore {
            Task { @MainActor in
                let owner = try? await profileStore.ensureOwnerProfileAndMigrate(
                    ownerName: "Me", colorTag: "gold")
                self.activeProfileID = owner?.id
                self.home?.activeProfileID = owner?.id
                await self.rebuildHome()
            }
        }
```

- [ ] **Step 2: Inject the active profile into playback** — in `makePlayer(for:engine:)`, change the
  coordinator construction (~line 266) to pass the active profile:

```swift
        let coordinator = PlaybackCoordinator(store: store, profileID: activeProfileID ?? "")
```

- [ ] **Step 3: Build + tests**

Run: `swift build --package-path Shared/DebridUI 2>&1 | grep -i warning || echo none` (none)
Run: `swift test --package-path Shared/DebridUI 2>&1 | tail -2` (green)

- [ ] **Step 4: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift
git commit -m "feat(ui): bootstrap owner profile on sign-in + inject it into Home/playback"
```

---

## Task 8: App Detail views — pass the active profile into `DetailStore`

**Files:**
- Modify: `Apps/SeretTV/Detail/DetailView.swift`, `Apps/SeretMobile/Detail/DetailScreen.swift`

- [ ] **Step 1: Thread `activeProfileID`** — in each file, find where `DetailStore(item:...,
  watch: session.watchStore, ...)` is constructed and add `profileID: session.activeProfileID`.
  (Search each file for `DetailStore(` to locate the exact call.)

- [ ] **Step 2: Regenerate + build both apps**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
```
Expected: both `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Apps/SeretTV/Detail/DetailView.swift Apps/SeretMobile/Detail/DetailScreen.swift
git commit -m "feat(apps): pass the active profile into DetailStore"
```

---

## Task 9: Full green sweep

**Files:** none (verification)

- [ ] **Step 1: Everything green, zero warnings**

```bash
swift test --package-path Packages/DebridCore 2>&1 | tail -2
swift test --package-path Shared/DebridUI 2>&1 | tail -2
swift build --package-path Packages/DebridCore 2>&1 | grep -i warning || echo "(no warnings)"
swift build --package-path Shared/DebridUI 2>&1 | grep -i warning || echo "(no warnings)"
xcodegen generate >/dev/null
xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)" | tail -1
xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)" | tail -1
```
Expected: all suites green, no warnings, both apps `BUILD SUCCEEDED`.

---

## Notes for the implementer

- After this slice: a single owner profile is auto-created, all progress is scoped to it, and
  CloudKit syncs `Profile`/`MyListEntry`/`WatchProgress` together. Behavior is unchanged for the
  user (one profile), but the data model is now per-profile.
- `activeProfileID` is `nil` only briefly at first launch before the bootstrap `Task` completes;
  Home shows empty and Detail skips record/progress until it's set, then `rebuildHome()` runs. This
  is acceptable transient state.
- Slice 3 = profile **switching** + **Who's-Watching** UI (uses `profileStore`, sets
  `activeProfileID`, re-injects + rebuilds). Slice 4 = My List (claim on add/play via `myListStore`,
  the All ⇄ Mine filter, Detail "Add to My List").
- Keep `deleteProgress(forContentKeys:)` cross-profile — a shared-library removal clears everyone.
