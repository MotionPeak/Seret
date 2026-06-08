# CloudKit Watch-Progress Sync (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync watch progress across a user's devices (Apple TV, iPhone, iPad) via SwiftData's native CloudKit, so Continue Watching and resume-position follow them under one Apple ID.

**Architecture:** The UI (Continue Watching rails, resume seek) already exists on this branch. This plan (1) makes `WatchProgress` reconcile cross-device duplicate rows last-write-wins, (2) switches the watch-progress `ModelContainer` to a shared private CloudKit database with a local-only fallback, (3) refreshes Home when a CloudKit change lands, and (4) seeds a forward-compat `profileID` field for Phase 2 profiles. CloudKit itself is verified on real devices; the dedupe logic is unit-tested in `DebridCore`.

**Tech Stack:** Swift 6, SwiftData (+ CloudKit mirroring), XcodeGen, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-06-08-cloudkit-watch-sync-design.md`

**Container ID:** `iCloud.com.solomons.seret` (shared by both app targets).

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `Packages/DebridCore/Sources/DebridCore/Persistence/WatchProgress.swift` | the `@Model` | add optional `profileID` |
| `Packages/DebridCore/Sources/DebridCore/Persistence/WatchProgressStore.swift` | read/write store | reconcile duplicates on read |
| `Packages/DebridCore/Tests/DebridCoreTests/WatchProgressReconcileTests.swift` | new test suite | duplicate-dedupe tests |
| `project.yml` | XcodeGen project | iCloud capability + entitlements + background mode on both app targets |
| `Apps/SeretTV/SeretTV.entitlements` (new) | tvOS entitlements | CloudKit container |
| `Apps/SeretMobile/SeretMobile.entitlements` (new) | iOS entitlements | CloudKit container |
| `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift` | app wiring | CloudKit container config + local fallback + remote-change → Home rebuild |
| `CLAUDE.md` | repo status | mark Phase 1 done + owner portal steps |

---

## Task 1: Add forward-compat `profileID` to the model

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Persistence/WatchProgress.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/WatchProgressReconcileTests.swift` (new)

- [ ] **Step 1: Write the failing test** — create the new test file:

```swift
import Testing
import Foundation
import SwiftData
@testable import DebridCore

// Nested under the serialized SwiftDataSuite parent (repo convention — multiple SwiftData
// suites must not run concurrently; two in-memory ModelContainers can SIGSEGV the runner).
extension SwiftDataSuite {
    @Suite struct WatchProgressReconcileTests {
        private func container() throws -> ModelContainer {
            try ModelContainer(for: WatchProgress.self,
                               configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }

        @Test func profileIDDefaultsToNil() throws {
            let row = WatchProgress(contentKey: "k")
            #expect(row.profileID == nil)
        }

        @Test func profileIDPersistsRoundTrip() throws {
            let c = try container()
            let ctx = ModelContext(c)
            let row = WatchProgress(contentKey: "k")
            row.profileID = "alice"
            ctx.insert(row)
            try ctx.save()
            let fetched = try ctx.fetch(FetchDescriptor<WatchProgress>()).first
            #expect(fetched?.profileID == "alice")
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter WatchProgressReconcileTests`
Expected: FAIL — compile error, `WatchProgress` has no member `profileID`.

- [ ] **Step 3: Add the field** — in `WatchProgress.swift`, add the stored property after `updatedAt` and a defaulted parameter to `init` (keep it optional + defaulted so CloudKit accepts it and no migration is needed):

```swift
    public var updatedAt: Date = Date(timeIntervalSince1970: 0)
    /// Phase-2 forward-compat: which profile owns this progress. `nil` = the owner/default
    /// profile. Unused in Phase 1 (the store neither reads nor writes it yet).
    public var profileID: String? = nil

    public init(contentKey: String = "", sourceKey: String = "",
                positionSeconds: Double = 0, durationSeconds: Double = 0,
                finished: Bool = false, updatedAt: Date = Date(timeIntervalSince1970: 0),
                profileID: String? = nil) {
        self.contentKey = contentKey
        self.sourceKey = sourceKey
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.finished = finished
        self.updatedAt = updatedAt
        self.profileID = profileID
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Packages/DebridCore --filter WatchProgressReconcileTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Persistence/WatchProgress.swift \
        Packages/DebridCore/Tests/DebridCoreTests/WatchProgressReconcileTests.swift
git commit -m "feat(core): add forward-compat profileID to WatchProgress"
```

---

## Task 2: Reconcile cross-device duplicates on read

CloudKit can't enforce uniqueness, so two devices can each create a row for the same
`contentKey`. Make the store keep the newest (`updatedAt`) and delete the rest on read.

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Persistence/WatchProgressStore.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/WatchProgressReconcileTests.swift`

- [ ] **Step 1: Write the failing tests** — append two tests inside the `WatchProgressReconcileTests` struct from Task 1. They insert duplicate rows directly via a context (bypassing the store's upsert) to simulate a CloudKit merge:

```swift
        /// Insert duplicate rows for one key straight into the store, as CloudKit would after a
        /// two-device merge.
        private func seedDuplicates(_ c: ModelContainer) throws {
            let ctx = ModelContext(c)
            ctx.insert(WatchProgress(contentKey: "dupe", sourceKey: "old", positionSeconds: 10,
                                     durationSeconds: 100, finished: false,
                                     updatedAt: Date(timeIntervalSince1970: 1)))
            ctx.insert(WatchProgress(contentKey: "dupe", sourceKey: "new", positionSeconds: 80,
                                     durationSeconds: 100, finished: false,
                                     updatedAt: Date(timeIntervalSince1970: 5)))
            try ctx.save()
        }

        @Test func progressReturnsNewestAndPrunesDuplicates() async throws {
            let c = try container()
            try seedDuplicates(c)
            let store = WatchProgressStore(modelContainer: c)
            let got = try await store.progress(forContentKey: "dupe")
            #expect(got?.positionSeconds == 80)        // the newest row wins
            #expect(got?.sourceKey == "new")
            #expect(try await store.allCount() == 1)   // the stale duplicate is gone
        }

        @Test func recentlyWatchedDedupesByContentKey() async throws {
            let c = try container()
            try seedDuplicates(c)
            let store = WatchProgressStore(modelContainer: c)
            let feed = try await store.recentlyWatched(limit: 20)
            #expect(feed.count == 1)                   // one entry per key, not two
            #expect(feed.first?.positionSeconds == 80)
        }
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --package-path Packages/DebridCore --filter WatchProgressReconcileTests`
Expected: FAIL — `allCount() == 2` (duplicate not pruned) and `feed.count == 2`.

- [ ] **Step 3: Implement reconcile-on-read** — in `WatchProgressStore.swift`, replace `fetchOne` so it keeps the newest match and deletes the rest, and rewrite `recentlyWatched` to dedupe by `contentKey` keeping the newest:

```swift
    /// Continue-Watching feed: unfinished rows that have progress, newest first, **deduped by
    /// contentKey** (CloudKit can sync more than one row per key from different devices).
    public func recentlyWatched(limit: Int) throws -> [WatchState] {
        guard limit > 0 else { return [] }
        let rows = try modelContext.fetch(FetchDescriptor<WatchProgress>(
            predicate: #Predicate { $0.finished == false && $0.positionSeconds > 0 },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
        var seen = Set<String>()
        var out: [WatchState] = []
        for row in rows where seen.insert(row.contentKey).inserted {   // newest-first → first wins
            out.append(WatchState(row))
            if out.count == limit { break }
        }
        return out
    }
```

```swift
    /// Newest row for `key`. If CloudKit merged duplicates, keep the newest (`updatedAt`) and
    /// delete the rest so the store converges to one row per key (last-write-wins).
    private func fetchOne(contentKey key: String) throws -> WatchProgress? {
        let matches = try modelContext.fetch(FetchDescriptor<WatchProgress>(
            predicate: #Predicate { $0.contentKey == key },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
        guard let survivor = matches.first else { return nil }
        if matches.count > 1 {
            for stale in matches.dropFirst() { modelContext.delete(stale) }
            try modelContext.save()
        }
        return survivor
    }
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter WatchProgressReconcileTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Run the FULL suite — no regressions, zero warnings**

Run: `swift test --package-path Packages/DebridCore`
Then: `swift build --package-path Packages/DebridCore 2>&1 | grep -i warning` (must print nothing)
Expected: all green (existing `WatchProgressStoreTests` / `WatchProgressDeleteTests` still pass — the `fetchOne` change preserves single-row behavior).

- [ ] **Step 6: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Persistence/WatchProgressStore.swift \
        Packages/DebridCore/Tests/DebridCoreTests/WatchProgressReconcileTests.swift
git commit -m "feat(core): reconcile duplicate watch-progress rows last-write-wins (CloudKit)"
```

---

## Task 3: Declare the CloudKit capability (project.yml + entitlements + background mode)

**Files:**
- Create: `Apps/SeretTV/SeretTV.entitlements`
- Create: `Apps/SeretMobile/SeretMobile.entitlements`
- Modify: `project.yml` (both app targets)

- [ ] **Step 1: Create the tvOS entitlements file** `Apps/SeretTV/SeretTV.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.com.solomons.seret</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
    <key>aps-environment</key>
    <string>development</string>
</dict>
</plist>
```

- [ ] **Step 2: Create the iOS entitlements file** `Apps/SeretMobile/SeretMobile.entitlements` — identical content to Step 1 (same container ID `iCloud.com.solomons.seret`, same keys). Copy the exact XML above.

- [ ] **Step 3: Wire entitlements + background mode into `project.yml`** — for the **SeretTV** target, add a `CODE_SIGN_ENTITLEMENTS` build setting and the background mode in `info.properties`. Under `targets.SeretTV.settings.base` add:

```yaml
        CODE_SIGN_ENTITLEMENTS: Apps/SeretTV/SeretTV.entitlements
```

And under `targets.SeretTV.info.properties` add:

```yaml
        UIBackgroundModes: [remote-notification]
```

- [ ] **Step 4: Repeat for SeretMobile** — under `targets.SeretMobile.settings.base` add:

```yaml
        CODE_SIGN_ENTITLEMENTS: Apps/SeretMobile/SeretMobile.entitlements
```

And under `targets.SeretMobile.info.properties` add:

```yaml
        UIBackgroundModes: [remote-notification]
```

> Note: tvOS delivers CloudKit changes primarily on foreground, not via background push — the
> background mode is harmless there and correct for iOS. Home also rebuilds on launch/foreground.

- [ ] **Step 5: Regenerate and build both targets**

Run:
```bash
xcodegen generate
xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build 2>&1 | tail -5
xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected: both `** BUILD SUCCEEDED **`. (If signing complains about the container in CLI, that's expected without the portal container yet — it resolves once the owner adds the container under the signing team in Xcode; the generated project is still correct. Note any signing error in the handoff rather than editing signing settings.)

- [ ] **Step 6: Commit**

```bash
git add project.yml Apps/SeretTV/SeretTV.entitlements Apps/SeretMobile/SeretMobile.entitlements
git commit -m "build: add CloudKit (iCloud.com.solomons.seret) capability to both app targets"
```

---

## Task 4: Switch the watch-progress container to CloudKit with a local fallback

**Files:**
- Modify: `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift` (the `enterSignedIn()` container line ~157, plus a new helper)

- [ ] **Step 1: Add the container-builder helper** — in `AppSession.swift`, add a private static helper and a container-ID constant (place near the other private members, e.g. just above `enterSignedIn()`):

```swift
    /// The shared CloudKit container both Seret apps sync through (one private DB per Apple ID).
    private static let cloudKitContainerID = "iCloud.com.solomons.seret"

    /// Builds the watch-progress store backed by CloudKit so progress syncs across the user's
    /// devices; falls back to a local-only store if iCloud/CloudKit is unavailable (e.g. no iCloud
    /// account) so the app still works offline and never loses local data.
    private static func makeWatchProgressStore() -> WatchProgressStore? {
        let schema = Schema([WatchProgress.self])
        let cloud = ModelConfiguration(schema: schema,
                                       cloudKitDatabase: .private(cloudKitContainerID))
        if let container = try? ModelContainer(for: schema, configurations: cloud) {
            return WatchProgressStore(modelContainer: container)
        }
        let local = ModelConfiguration(schema: schema)
        if let container = try? ModelContainer(for: schema, configurations: local) {
            return WatchProgressStore(modelContainer: container)
        }
        return nil
    }
```

- [ ] **Step 2: Use the helper in `enterSignedIn()`** — replace:

```swift
        let concreteStore = (try? ModelContainer(for: WatchProgress.self))
            .map { WatchProgressStore(modelContainer: $0) }
```

with:

```swift
        let concreteStore = Self.makeWatchProgressStore()
```

- [ ] **Step 3: Verify the package + app still build**

Run:
```bash
swift build --package-path Shared/DebridUI 2>&1 | tail -3
swift build --package-path Shared/DebridUI 2>&1 | grep -i warning   # must print nothing
```
Expected: builds clean, no warnings. (`ModelConfiguration(schema:cloudKitDatabase:)` and `.private(_:)` are SwiftData APIs available on the iOS/tvOS 18 / macOS 14 floor.)

- [ ] **Step 4: Verify DebridUI tests still pass** (the store change is config-only; view-model suites must stay green)

Run: `swift test --package-path Shared/DebridUI 2>&1 | tail -5`
Expected: all green (48+ tests).

- [ ] **Step 5: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift
git commit -m "feat(ui): back watch progress with CloudKit, fall back to local-only without iCloud"
```

---

## Task 5: Refresh Home when a CloudKit change lands

CloudKit is eventually-consistent — progress from another device arrives via a remote-change
notification. Re-run `HomeStore.rebuild` so Continue Watching updates live.

**Files:**
- Modify: `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift`

- [ ] **Step 1: Add the observer field** — near the other private fields (e.g. after `private var torrents: TorrentsClient?`):

```swift
    /// Single, app-lifetime observer that rebuilds Home when CloudKit imports remote changes.
    private var remoteChangeObserver: NSObjectProtocol?
```

- [ ] **Step 2: Add the observer + rebuild methods** — add to `AppSession`:

```swift
    /// Rebuild the Home rails from the current library + (possibly just-synced) watch progress.
    private func rebuildHome() async {
        guard let library = libraryStore, let home else { return }
        await home.rebuild(movies: library.movies, shows: library.shows)
    }

    /// Install once: when the persistent store imports CloudKit changes, refresh Home so a title
    /// watched on another device shows up in Continue Watching without relaunch. `[weak self]` +
    /// app-lifetime single instance → no retain cycle, no teardown needed.
    private func observeRemoteChanges() {
        guard remoteChangeObserver == nil else { return }
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.rebuildHome() }
        }
    }
```

- [ ] **Step 3: Call it where Home is composed** — in `enterSignedIn()`, immediately after the existing `home = watchStore.map { HomeStore(watch: $0) }` line, add:

```swift
        observeRemoteChanges()
```

- [ ] **Step 4: Verify build (package, zero warnings) and tests**

Run:
```bash
swift build --package-path Shared/DebridUI 2>&1 | grep -i warning    # nothing
swift test --package-path Shared/DebridUI 2>&1 | tail -5             # green
```
Expected: clean build, tests green. (`NSPersistentStoreRemoteChange` is posted by the Core Data store underlying SwiftData's CloudKit mirroring.)

- [ ] **Step 5: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift
git commit -m "feat(ui): refresh Home (Continue Watching) when CloudKit syncs remote changes"
```

---

## Task 6: Final verification + docs

**Files:**
- Modify: `CLAUDE.md` (status + owner portal steps)

- [ ] **Step 1: Full green sweep** — run everything once more:

```bash
swift test --package-path Packages/DebridCore 2>&1 | tail -5
swift test --package-path Shared/DebridUI 2>&1 | tail -5
swift build --package-path Packages/DebridCore 2>&1 | grep -i warning   # nothing
xcodegen generate
xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build 2>&1 | tail -3
xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
```
Expected: all suites green, no warnings, both apps `BUILD SUCCEEDED`.

- [ ] **Step 2: Document status + the owner's one-time CloudKit-console steps** — add a short section to `CLAUDE.md` (under Status / Open follow-ups) recording:
  - Phase 1 (CloudKit watch-progress sync) built on `feat/cloudkit-sync`; dedupe unit-tested; on-device sync **owner-pending**.
  - Owner one-time steps: (a) ensure the signing team owns the CloudKit container `iCloud.com.solomons.seret` (add the iCloud→CloudKit capability in Xcode once, which creates it); (b) first dev run materializes the development schema; (c) **deploy the schema to Production** in the CloudKit console before any TestFlight/release build.
  - On-device DoD: play+stop a title on the Apple TV → it resumes at the right position and appears in Continue Watching on the iPhone/iPad (and vice-versa), all on one Apple ID.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: record CloudKit watch-sync Phase 1 status + owner CloudKit-console steps"
```

---

## On-device verification (owner, after merge)

CloudKit can't be exercised in the simulator without an iCloud account + provisioned container, so
the real DoD is on the owner's hardware:

1. In Xcode, confirm the **iCloud → CloudKit** capability is on for both targets with container
   `iCloud.com.solomons.seret`, signed by a team that owns it.
2. Sign all devices into the **same Apple ID**.
3. On the Apple TV: play a movie ~2 min, stop. On the iPhone: open Seret → it appears in
   **Continue Watching** and **resumes** at ~2 min. Reverse the direction to confirm two-way.
4. Before release: **deploy the CloudKit schema to Production**.

## Notes for the implementer

- Do **not** touch the `DownloadRequest` container (also in `enterSignedIn()`): downloads are
  device-local and intentionally **not** synced.
- Keep `DebridCore` CloudKit-free — all CloudKit config lives in the app-wiring layer (`AppSession`
  in `DebridUI`). The package stays pure and `swift test`-able on the dev Mac.
- New SwiftData test suites **must** nest under `extension SwiftDataSuite { @Suite struct … }`
  (repo convention) — Task 1/2's file already does this.
- Run the **full** `swift test` before each commit that touches the brain, not just `--filter`.
```
