# Seret — Resume + Continue Watching + CloudKit Watch-Progress Sync (Phase 1)

> Design spec. Status: **approved 2026-06-08**, ready for implementation planning.
> Owner: Shahar. Branch: `feat/cloudkit-sync` (off `feat/stage2-search-add`).

## Goal

Make a user's **watch progress follow them across all their devices** (Apple TV, iPhone,
iPad) so they can stop a movie on one and resume it on another, and see one shared
**Continue Watching** shelf everywhere — all under a single Apple ID via CloudKit.

This is **Phase 1** of a two-phase request. Phase 2 (multi-user *profiles* on the shared
Real-Debrid account — each profile sees only what it added, with its own continuation) is
**out of scope here** but the data model below is built forward-compatible for it.

## Context — what already exists (do not rebuild)

On the base branch (`feat/stage2-search-add`), the following are **already built and wired**:

- **Resume-to-position.** `PlaybackCoordinator` (DebridCore) seeks to the last saved position
  on replay; `PlayerModel` saves every ~5s and marks finished at ~95%.
- **Continue Watching + Recently Added rails.** `Shared/DebridUI/.../Home/HomeStore.swift`
  composes both rails from `WatchProgressStore` + the library. Rendered and wired on **tvOS**
  (`Apps/SeretTV/Home/HomeScreen.swift`, a Home tab in `LibraryShell` with a "Resume" hero)
  and **mobile** (`Apps/SeretMobile/Home/HomeScreen.swift`).
- **CloudKit-ready model.** `WatchProgress` (`@Model`) already has every property defaulted,
  no unique constraint, no required relationship — exactly CloudKit's requirements. The author
  left the note: *"Stage 3 cross-device sync is a config flip."*

So Phase 1 is **not** new UI. It is: turn on CloudKit, handle the one correctness issue it
introduces, refresh Home when a sync arrives, and verify resume/Continue-Watching behave.

## Hard prerequisite (confirmed)

- Owner is enrolled in the **paid Apple Developer Program** (CloudKit containers + the iCloud
  entitlement require it). ✓ confirmed.
- All target devices are signed into the **same Apple ID** (sync follows the Apple account,
  not a Seret login). ✓ expected for a personal app.

## Approach

**SwiftData-native CloudKit**, not a hand-rolled `CKRecord` sync engine. The models were
purpose-built for this; a manual sync layer would discard that design for no benefit. The
change is a `ModelConfiguration` + entitlements, not a new subsystem.

## Design

### 1. Switch the watch-progress container to CloudKit

Today, in `Shared/DebridUI/.../Shell/AppSession.swift`:

```swift
let concreteStore = (try? ModelContainer(for: WatchProgress.self))
    .map { WatchProgressStore(modelContainer: $0) }
```

Change to a CloudKit-backed configuration pointing at a **shared private database**:

- Container identifier: **`iCloud.com.solomons.seret`** (one container, used by *both* app
  targets even though their bundle IDs differ — `com.solomons.seret.tv` and `.mobile`).
- `ModelConfiguration(..., cloudKitDatabase: .private("iCloud.com.solomons.seret"))`.
- Add to **both** app targets in `project.yml`:
  - iCloud capability with **CloudKit** service + the container identifier.
  - **Background mode: remote notifications** (so CloudKit can push change pings).
  - The matching `*.entitlements` file (`com.apple.developer.icloud-services`,
    `com.apple.developer.icloud-container-identifiers`, `aps-environment`).

The construction lives once in the shared `AppSession`, so both apps inherit it. The container
ID is a single shared constant (e.g. `Secrets`/a constants file), not duplicated per app.

### 2. Reconcile cross-device duplicates (the one correctness piece)

CloudKit **cannot enforce uniqueness**. Two devices can each insert a `WatchProgress` row for
the same `contentKey` before they sync, yielding duplicate rows. The current
`WatchProgressStore.fetchOne` returns `.first` — which may be the *stale* duplicate.

Fix — **reconcile on read**, last-write-wins by `updatedAt`, inside `WatchProgressStore`:

- `fetchOne(contentKey:)` → when more than one row matches, keep the row with the newest
  `updatedAt`, delete the others, return the survivor.
- `recentlyWatched(limit:)` → dedupe by `contentKey`, keeping the newest per key, before
  applying the limit.
- `record(...)` already upserts via `fetchOne`, so it inherits the reconcile automatically.

This is pure SwiftData logic and is **unit-tested in `DebridCore`** with an in-memory store
(no CloudKit needed): insert duplicates → assert the survivor is the newest and the others are
gone; assert `recentlyWatched` returns one entry per key.

### 3. Refresh Home when a sync lands

CloudKit is eventually-consistent: progress made on another device arrives seconds later. SwiftData
posts a remote-change signal when the store imports CloudKit changes. Observe it (the
`NSPersistentStoreRemoteChange` notification) and re-run `HomeStore.rebuild(...)` so Continue
Watching updates live instead of only on next launch. Keep this lightweight and debounced; it
reuses the existing `rebuild` path (already triggered on library change).

### 4. Graceful fallback

If no iCloud account is available, or the CloudKit container fails to initialize, fall back to a
**local-only** `ModelContainer` for `WatchProgress` (today's behavior). The app must never crash
or lose local data because iCloud is unavailable; sync simply doesn't happen until an account
exists. Implemented as: try the CloudKit configuration; on failure, retry with a plain local
configuration; log once.

### 5. Forward-compat for Phase 2 (profiles)

Add to `WatchProgress` now (unused in Phase 1):

```swift
public var profileID: String? = nil   // nil = the owner/default profile
```

Optional + defaulted, so it satisfies CloudKit and requires **no migration** when Phase 2 starts
filtering progress by profile. Existing/old rows read back as `nil` = the owner profile. The DTO
(`WatchState`) and `WatchKey` are unchanged in Phase 1; the store does not yet read or write
`profileID`.

## Components touched

| Unit | Change |
|---|---|
| `DebridCore/Persistence/WatchProgress.swift` | add optional `profileID` |
| `DebridCore/Persistence/WatchProgressStore.swift` | reconcile-on-read dedupe in `fetchOne` + `recentlyWatched` |
| `DebridUI/Shell/AppSession.swift` | CloudKit `ModelConfiguration` + local fallback; observe remote-change → `HomeStore.rebuild` |
| `project.yml` (both app targets) | iCloud/CloudKit capability, container id, remote-notification background mode, entitlements files |
| new `*.entitlements` × 2 | iCloud services + container id + `aps-environment` |
| `DebridCoreTests` | duplicate-reconcile unit tests |

No change to `HomeStore`, `HomeScreen` (tvOS/mobile), `PlaybackCoordinator`, or `PlayerModel` —
they already do the right thing and read through `WatchProgressStore`.

## Testing & verification

- **Unit (CI-able, no iCloud):** duplicate-reconcile tests in `DebridCore` (in-memory SwiftData,
  nested under the `SwiftDataSuite` serialized parent per repo convention). Existing
  `WatchProgressStore` tests must stay green. Run the **full** `swift test` suite, zero warnings.
- **Build:** `xcodegen generate` → `xcodebuild build` for both schemes, zero warnings.
- **On-device DoD (owner-pending, like the player):** CloudKit can't be verified in the simulator
  without iCloud + entitlements. Owner verifies on real devices signed into one Apple ID: play and
  stop a title on the Apple TV → it appears in Continue Watching and resumes at the right position
  on the iPhone/iPad (and vice-versa).

## Owner one-time portal steps (documented in the plan, done by owner)

1. Create the CloudKit container **`iCloud.com.solomons.seret`** (Xcode auto-creates it with the
   paid account when the capability is added, or via the Developer portal).
2. First dev run materializes the **development** CloudKit schema from the model.
3. Before any TestFlight/release build, **deploy the schema to Production** in the CloudKit console.

## Out of scope (Phase 2 and beyond)

- Multi-user **profiles** (Netflix-style on the shared RD account): a "Who's watching?" screen,
  per-profile libraries ("only what they added"), per-profile continuation, profile CRUD on all
  three apps, and per-profile CloudKit record scoping. The `profileID` field seeds this.
- Syncing **last-used audio/subtitle track** preference (a separate open follow-up); it can ride
  the same record later but is not part of Phase 1.
- Syncing the **library cache** — unnecessary; the library is derived per-device from the shared
  Real-Debrid account.
