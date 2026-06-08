# Seret — Multi-User Profiles (Phase 2)

> Design spec. Status: **approved 2026-06-08**, ready for implementation planning.
> Owner: Shahar. Branch: `feat/profiles` (off `main`).
> Follows Phase 1 ([`2026-06-08-cloudkit-watch-sync-design.md`](2026-06-08-cloudkit-watch-sync-design.md)).

## Goal

Let several people share one Seret install (one Real-Debrid account) but each get their **own
Continue Watching, own resume positions, and own curated shelf ("My List")** — Netflix-style
profiles. Pick "who's watching" at launch; switch anytime. All profile data syncs across devices
via the CloudKit container turned on in Phase 1.

## Model decision (locked in brainstorming)

- **(B) Shared library + personal layer.** The RD account is one shared pool, so **every profile
  sees the whole library and all of Browse/Search**. Profiles do *not* hide content.
- **(ii) Claim by add-or-play.** A title joins a profile's **My List** when that profile **adds**
  it (Search → Add) *or* **plays** it. A manual add/remove toggle also exists.
- "Show only what they added" is delivered as the **My List** view — a filter on the existing
  **My Library** tab, defaulting to *Mine* when more than one profile exists.

## What is per-profile vs shared

| | Scope |
|---|---|
| Full Movies/TV library (**My Library** tab) | **Shared** (one RD account) |
| Browse / Search (TMDB discovery, Movies/TV tabs) | **Shared** |
| **Continue Watching + resume position** (Home) | **Per-profile** (`WatchProgress.profileID`) |
| **My List** (claimed titles) | **Per-profile** (new `MyListEntry`) |
| Profile identity (name, color) | **Per-profile** (new `Profile`) |

## Active profile = device-local

Each device remembers **who's watching** (`UserDefaults`), so switching to a kid's profile on the
iPhone doesn't flip the Apple TV mid-movie. The **profile roster** itself syncs via CloudKit; the
*selection* does not. Netflix-on-TV behaves the same way.

## "Who's watching?"

- Shown after sign-in / on launch **only when more than one profile exists**. With a single (owner)
  profile, it's skipped entirely — zero friction for solo use.
- Switch anytime via a profile button in the shell (tvOS top bar / iOS, and Settings).

## Migration — nothing is lost

On first launch after this ships, if no `Profile` rows exist, Seret **auto-creates one owner
profile** and assigns every existing `WatchProgress` row (the Phase-1 `profileID == nil` rows) to
it. The user keeps all their progress; they're simply "profile 1." Active profile is set to the
owner on that device.

## Data model (new — CloudKit-synced in the Phase-1 private DB)

All models follow the CloudKit rules already established: every property optional/defaulted, no
unique constraints, no required relationships. Flat rows (no SwiftData relationships) keep CloudKit
simple and dedupe explicit.

```
Profile         @Model   id: String (UUID) · name: String · colorTag: String · createdAt: Date
MyListEntry     @Model   id: String ("<profileID>|<contentKey>") · profileID · contentKey · addedAt: Date
WatchProgress            (existing) — profileID now WRITTEN and FILTERED on
```

- `ProfileStore` (`@ModelActor`) — CRUD the roster: `all()`, `create(name:color:)`, `rename`,
  `delete(id:)` (cascade: also delete that profile's `MyListEntry` + `WatchProgress` rows),
  `ensureOwnerProfileAndMigrate()` (the migration above; idempotent).
- `MyListStore` (`@ModelActor`) — `claim(profileID:contentKey:)` (upsert, dedupe like Phase 1),
  `unclaim(profileID:contentKey:)`, `contentKeys(forProfile:)`, `isClaimed(profileID:contentKey:)`.
- `WatchProgressStore` — methods gain a `profileID` argument; reads filter by it and the
  duplicate-reconcile key becomes **(contentKey, profileID)**.

## Component changes

| Unit | Change |
|---|---|
| `DebridCore/Profiles/Profile.swift` (new) | `Profile` `@Model` + `ProfileDTO` Sendable snapshot |
| `DebridCore/Profiles/MyListEntry.swift` (new) | `MyListEntry` `@Model` |
| `DebridCore/Profiles/ProfileStore.swift` (new) | roster CRUD + owner migration |
| `DebridCore/Profiles/MyListStore.swift` (new) | claim/unclaim/list |
| `DebridCore/Persistence/WatchProgressStore.swift` | thread `profileID`; reconcile per (key, profileID) |
| `DebridUI/Profiles/ActiveProfileStore.swift` (new) | device-local selection (`UserDefaults`) + roster cache (`@Observable`) |
| `DebridUI/Detail/WatchProgressProviding.swift` | seam methods gain `profileID` |
| `DebridUI/Home/HomeStore.swift` | `rebuild` reads `recentlyWatched(profileID:)` |
| `DebridUI/Library/LibraryStore.swift` | expose a `myList(of:)` filter / claimed-set membership |
| `DebridUI/Shell/AppSession.swift` | compose Profile/MyList stores; inject active profile into Home/Detail/playback; reconfigure feeds on profile switch |
| `DebridUI/Profiles/WhoIsWatchingView.swift` (new) | shared who's-watching + add-profile |
| `DebridUI/Profiles/ProfileManagerView.swift` (new) | create/rename/delete/color |
| `Apps/SeretTV/*`, `Apps/SeretMobile/*` | thin hosts: who's-watching gate, profile switch button, My-List filter pill, "Add to My List" in Detail |
| Stage 2 `AddStore` + playback (`PlaybackCoordinator`/`PlayerModel`) | claim into My List on add + on play |

## Data flow

1. **Launch / sign-in:** `AppSession` builds the brain, runs `ensureOwnerProfileAndMigrate()`, loads
   the roster. If `roster.count > 1` and no valid device selection → present **Who's Watching**.
   Else use the stored/owner active profile.
2. **Active profile set:** `AppSession` injects `profileID` into `HomeStore`, `DetailStore`, and the
   playback wiring, then rebuilds Home. Switching profiles re-injects + rebuilds.
3. **Play:** `PlaybackCoordinator` records progress with the active `profileID` and `MyListStore`
   claims the title.
4. **Add (Stage 2):** `AddStore.add` also claims the title for the active profile.
5. **My List view:** **My Library** tab gains an `All ⇄ Mine` pill; *Mine* filters `store.movies`/
   `store.shows` to the active profile's claimed `contentKeys`.

## Error handling / edge cases

- **No CloudKit / local fallback (Phase 1):** profiles still work locally; they just don't sync.
- **Delete the active/owner profile:** block deleting the **last** profile; if the active profile is
  deleted, fall back to the first remaining and clear the device selection.
- **Stale device selection** (profile deleted on another device, synced away): if the stored active
  id isn't in the roster, drop to Who's-Watching (or owner if solo).
- **Claim dedupe:** `MyListEntry.id = "<profileID>|<contentKey>"` makes claims idempotent; reconcile
  duplicates last-write-wins like Phase 1.
- **Removing a title from My Library** (existing RD-delete feature): also unclaim it from all
  profiles' My Lists and delete its progress (extend the existing purge).

## Testing

- **Unit (DebridCore, in-memory SwiftData, no CloudKit):** `ProfileStore` CRUD + cascade-delete +
  idempotent owner-migration; `MyListStore` claim/unclaim/dedupe/list; `WatchProgressStore`
  per-profile scoping + per-(key,profileID) reconcile. Nest under `SwiftDataSuite`.
- **Unit (DebridUI, host-free):** `ActiveProfileStore` selection persistence + roster-staleness
  fallback; `HomeStore` rebuild scoped by profile (fakes); My-List filter membership.
- **Build:** `xcodegen generate` + `xcodebuild build` both schemes, zero warnings.
- **On-device (owner):** create a 2nd profile; confirm separate Continue Watching + My List;
  confirm the roster syncs to another device (same Apple ID) while the *selection* stays per-device.

## Implementation slices (the plan will split these)

1. **Brain models + stores** — `Profile`, `MyListEntry`, `ProfileStore`, `MyListStore` (+ migration), all unit-tested.
2. **Per-profile watch progress** — thread `profileID` through `WatchProgressStore` + seam; reconcile per (key, profileID).
3. **Active profile state + wiring** — `ActiveProfileStore`, `AppSession` composition + injection + switch-rebuild; Home scoped.
4. **My List** — claim on add+play, `All ⇄ Mine` filter on My Library, Detail "Add to My List" toggle.
5. **Profile UI** — `WhoIsWatchingView` + `ProfileManagerView` + per-app hosts (gate, switch button).

Each slice compiles and tests green on its own; UI verification (sim screenshots / on-device) is
owner-pending where the simulator can't reach it, per repo convention.

## Out of scope (YAGNI for v1)

PIN/lock, kids content-restrictions, per-profile RD tokens, avatar photo uploads, profile-count
caps, per-profile subtitle/audio preferences (the global track-preference work stays global for now).
