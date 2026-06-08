# Profiles — Slice 4 (My List) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each profile a personal **My List** — titles it claims by **playing** them (auto) or **adding** them via a Detail toggle — surfaced as an **All ⇄ Mine** filter on the My Library tab.

**Architecture:** A `MyListProviding` seam (DebridUI) over `MyListStore`. `AppSession.makePlayer` auto-claims the played title. `DetailStore` gains an in-My-List state + toggle (TDD with a fake). Each app's My Library screen gets an All ⇄ Mine pill that filters the shared library to the active profile's claimed content keys (loaded from `session.myListStore`), defaulting to *Mine* when more than one profile exists.

**Tech Stack:** Swift 6, SwiftUI, SwiftData (behind seams), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-06-08-profiles-design.md` (Slice 4 — My List). Builds on Slices 1–3.

**Deviation from spec (intentional):** the spec said "claim by **add or play**" where *add* = the Stage-2 search→RD add. But a title's `contentKey` (`MediaItem.id`) is derived by `LibraryBuilder` *after* RD groups the torrent — it isn't known at add time, so mapping a Stage-2 add to its eventual content key is unreliable. Instead: **claim on play** (reliable — `PlaybackRequest.contentKey` is the real id) **+ a manual "Add to My List" toggle** on Detail (explicit curation). Same user outcome; no fragile add-time mapping. (The seam supports a future add-time claim if a reliable mapping appears.)

**Conventions:** TDD for `DetailStore` (host-free); seam + AppSession + SwiftUI build-verified. Zero warnings.

---

## File Structure

| File | Change |
|---|---|
| `Shared/DebridUI/Sources/DebridUI/Profiles/MyListProviding.swift` (new) | Sendable seam over `MyListStore` |
| `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift` | claim-on-play in `makePlayer` |
| `Shared/DebridUI/Sources/DebridUI/Detail/DetailStore.swift` | `inMyList` state + `toggleMyList(contentKey:)` |
| `Shared/DebridUI/Tests/DebridUITests/DetailStoreTests.swift` | My-List toggle tests |
| `Apps/SeretTV/Detail/MovieDetailView.swift` (+ Show) | "Add to My List" / "In My List" button |
| `Apps/SeretTV/Library/MyLibraryScreen.swift` | All ⇄ Mine pill + filter |
| `Apps/SeretTV/Detail/DetailView.swift` | pass `myList: session.myListStore` |
| `Apps/SeretMobile/Detail/*` | "Add to My List" button + pass `myList` |
| `Apps/SeretMobile/Library/*` (My Library view) | All ⇄ Mine filter |

---

## Task 1: `MyListProviding` seam

**Files:**
- Create: `Shared/DebridUI/Sources/DebridUI/Profiles/MyListProviding.swift`

- [ ] **Step 1: Write the seam + conformance**

```swift
import DebridCore
import Foundation

/// Sendable seam over `MyListStore` so `DetailStore` is testable without SwiftData.
public protocol MyListProviding: Sendable {
    func claim(profileID: String, contentKey: String) async throws
    func unclaim(profileID: String, contentKey: String) async throws
    func isClaimed(profileID: String, contentKey: String) async throws -> Bool
    func contentKeys(forProfile profileID: String) async throws -> [String]
}

extension MyListStore: MyListProviding {
    // `unclaim` / `isClaimed` / `contentKeys` satisfy directly. Provide the no-`at:` `claim`.
    public func claim(profileID: String, contentKey: String) async throws {
        try claim(profileID: profileID, contentKey: contentKey, at: Date())
    }
}
```

- [ ] **Step 2: Build (zero warnings)**

Run: `swift build --package-path Shared/DebridUI 2>&1 | grep -iE "error:|warning:" || echo clean`
Expected: `clean`.

- [ ] **Step 3: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Profiles/MyListProviding.swift
git commit -m "feat(ui): MyListProviding seam over MyListStore"
```

---

## Task 2: `DetailStore` — In-My-List state + toggle

**Files:**
- Modify: `Shared/DebridUI/Sources/DebridUI/Detail/DetailStore.swift`
- Test: `Shared/DebridUI/Tests/DebridUITests/DetailStoreTests.swift`

- [ ] **Step 1: Write the failing test** — add a fake + test to `DetailStoreTests`. Near the top
  (with the other fakes) add:

```swift
private actor FakeMyList: MyListProviding {
    private var claimed: Set<String> = []
    init(_ seed: Set<String> = []) { claimed = seed }
    func claim(profileID: String, contentKey: String) async throws { claimed.insert("\(profileID)|\(contentKey)") }
    func unclaim(profileID: String, contentKey: String) async throws { claimed.remove("\(profileID)|\(contentKey)") }
    func isClaimed(profileID: String, contentKey: String) async throws -> Bool { claimed.contains("\(profileID)|\(contentKey)") }
    func contentKeys(forProfile profileID: String) async throws -> [String] {
        claimed.filter { $0.hasPrefix("\(profileID)|") }.map { String($0.dropFirst(profileID.count + 1)) }
    }
}
```

  And inside `DetailStoreTests`:

```swift
    @Test func toggleMyListClaimsThenUnclaims() async {
        let m = movie("1", sources: [source("t", "1080p")])
        let key = WatchKey.content(forMovie: m)
        let list = FakeMyList()
        let store = DetailStore(item: m, details: FakeDetails(movie: .success(movieDetails())),
                                watch: nil, profileID: "p1", myList: list)
        await store.loadMyList(contentKey: key)
        #expect(store.inMyList == false)
        await store.toggleMyList(contentKey: key)
        #expect(store.inMyList == true)
        #expect(await (try? list.isClaimed(profileID: "p1", contentKey: key)) == true)
        await store.toggleMyList(contentKey: key)
        #expect(store.inMyList == false)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Shared/DebridUI --filter DetailStoreTests`
Expected: FAIL — `DetailStore.init` has no `myList:`; no `inMyList`/`loadMyList`/`toggleMyList`.

- [ ] **Step 3: Implement** — in `DetailStore.swift`:
  - Add a stored `private let myList: MyListProviding?` and an `inMyList` observable:

```swift
    private let myList: MyListProviding?
    public private(set) var inMyList = false
```

  - Add `myList: MyListProviding? = nil` to `init` (after `profileID`), assigning `self.myList = myList`.
  - Add the load + toggle methods:

```swift
    /// Load whether the active profile has claimed this title (for the Add-to-My-List button).
    public func loadMyList(contentKey: String) async {
        guard let myList, let profileID else { inMyList = false; return }
        inMyList = (try? await myList.isClaimed(profileID: profileID, contentKey: contentKey)) ?? false
    }

    /// Add or remove this title from the active profile's My List.
    public func toggleMyList(contentKey: String) async {
        guard let myList, let profileID else { return }
        if inMyList {
            try? await myList.unclaim(profileID: profileID, contentKey: contentKey)
            inMyList = false
        } else {
            try? await myList.claim(profileID: profileID, contentKey: contentKey)
            inMyList = true
        }
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Shared/DebridUI --filter DetailStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Detail/DetailStore.swift \
        Shared/DebridUI/Tests/DebridUITests/DetailStoreTests.swift
git commit -m "feat(ui): DetailStore In-My-List state + toggle (claim/unclaim)"
```

---

## Task 3: `AppSession` — claim on play

**Files:**
- Modify: `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift`

- [ ] **Step 1: Auto-claim the played title** — in `makePlayer(for:engine:)`, right after the
  `guard let torrents, let store = watchProgressStore else { return nil }` line, add:

```swift
        // Playing a title claims it into the active profile's My List (add-or-play, rule ii).
        if let myListStore, let pid = activeProfileID {
            let key = request.contentKey
            Task { try? await myListStore.claim(profileID: pid, contentKey: key) }
        }
```

- [ ] **Step 2: Build + tests**

Run: `swift build --package-path Shared/DebridUI 2>&1 | grep -iE "error:|warning:" || echo clean` (clean)
Run: `swift test --package-path Shared/DebridUI 2>&1 | tail -2` (green)

- [ ] **Step 3: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift
git commit -m "feat(ui): playing a title claims it into the active profile's My List"
```

---

## Task 4: tvOS — Detail "Add to My List" button + My Library All ⇄ Mine filter

**Files:**
- Modify: `Apps/SeretTV/Detail/DetailView.swift` (pass `myList`), `Apps/SeretTV/Detail/MovieDetailView.swift` + `ShowDetailView.swift` (button), `Apps/SeretTV/Library/MyLibraryScreen.swift` (filter)

- [ ] **Step 1: Pass the seam into `DetailStore`** — in `DetailView.swift`, add `myList:` to the
  init and the `DetailStore(...)` call, and a `.task` to load it. Read the file, then:
  - init param: `myList: MyListProviding? = nil` (after `profileID`); pass `myList: myList` into `DetailStore(...)`.
  - In `LibraryShell.swift` where `DetailView(...)` is built, add `myList: session.myListStore`.
  - Add `.task { await store.loadMyList(contentKey: WatchKey.content(forMovie: store.item)) }` for
    movies (use the movie content key; for shows the button can be omitted or use the show id).

- [ ] **Step 2: Add the button** — in `MovieDetailView.swift`, near the Play/Resume actions, add a
  button bound to the store (read the file for the exact action-row style):

```swift
            Button {
                Task { await store.toggleMyList(contentKey: WatchKey.content(forMovie: store.item)) }
            } label: {
                Label(store.inMyList ? "In My List" : "Add to My List",
                      systemImage: store.inMyList ? "checkmark" : "plus")
            }
```

- [ ] **Step 3: My Library All ⇄ Mine filter** — in `MyLibraryScreen.swift`, add an `All`/`Mine`
  selector alongside the existing Movies/TV pills and filter the items. Read the file first; then:
  - Add `@State private var mineOnly = false` and `@State private var myKeys: Set<String> = []`.
  - On appear (and on profile change): `myKeys = Set((try? await session.myListStore?.contentKeys(forProfile: session.activeProfileID ?? "")) ?? [])`; default `mineOnly = (session.activeProfiles?.roster.count ?? 0) > 1`.
  - Add a two-pill `All` / `Mine` selector (reuse `SeretPillStyle`).
  - Filter the items passed to `LibraryScreen`: when `mineOnly`, `items.filter { myKeys.contains($0.id) }`.

- [ ] **Step 4: Regenerate + build tvOS**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -4
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Apps/SeretTV/Detail/DetailView.swift Apps/SeretTV/Detail/MovieDetailView.swift \
        Apps/SeretTV/Shell/LibraryShell.swift Apps/SeretTV/Library/MyLibraryScreen.swift
git commit -m "feat(tvos): Add-to-My-List on Detail + All/Mine filter on My Library"
```

---

## Task 5: iOS — Detail "Add to My List" button + My Library All ⇄ Mine filter

**Files:**
- Modify: `Apps/SeretMobile/Detail/DetailScreen.swift` (pass `myList` + `.task` load), the mobile
  movie-detail view (button), `Apps/SeretMobile/Shell/RootView.swift` (pass `myList`), the mobile
  My Library view (filter).

- [ ] **Step 1: Pass the seam** — in `DetailScreen.swift` add `myList: MyListProviding? = nil` to
  init and into the `DetailStore(...)` call; in `RootView.swift` pass `myList: session.myListStore`;
  add `.task { await store.loadMyList(contentKey: WatchKey.content(forMovie: store.item)) }`.

- [ ] **Step 2: Add the button** — in the mobile movie-detail view (read it for the exact
  layout/style), add a touch button mirroring tvOS:

```swift
            Button {
                Task { await store.toggleMyList(contentKey: WatchKey.content(forMovie: store.item)) }
            } label: {
                Label(store.inMyList ? "In My List" : "Add to My List",
                      systemImage: store.inMyList ? "checkmark" : "plus")
            }
```

- [ ] **Step 3: My Library All ⇄ Mine filter** — in the mobile My Library view (find it under
  `Apps/SeretMobile/Library`), add an `All`/`Mine` segmented control (or two pills) + the same
  `myKeys`/`mineOnly` load + filter as tvOS Task 4 Step 3 (default Mine when >1 profile).

- [ ] **Step 4: Regenerate + build iOS**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -4
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Apps/SeretMobile/Detail Apps/SeretMobile/Shell/RootView.swift Apps/SeretMobile/Library
git commit -m "feat(ios): Add-to-My-List on Detail + All/Mine filter on My Library"
```

---

## Task 6: Full green sweep

**Files:** none (verification)

- [ ] **Step 1: Everything green, zero warnings, both apps build**

```bash
swift test --package-path Packages/DebridCore 2>&1 | tail -1
swift test --package-path Shared/DebridUI 2>&1 | tail -1
swift build --package-path Shared/DebridUI 2>&1 | grep -i warning || echo "(no warnings)"
xcodegen generate >/dev/null
xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)" | tail -1
xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)" | tail -1
```
Expected: all green, no warnings, both `BUILD SUCCEEDED`.

---

## Notes for the implementer

- **Owner-pending (sim/device):** screenshots — Add-to-My-List on a title, then My Library → Mine
  shows it; play a title and confirm it appears under Mine. Needs the owner's RD token for live
  library data.
- Shows: the My-List button uses the show's `id` as content key (a show-level claim). The simplest
  correct choice; per-episode claims aren't needed for "My List".
- Keep the My Library filter logic per-app (it's a few lines); both read `session.myListStore` for
  the active profile's claimed keys.
- After this slice, Phase 2 (profiles) is feature-complete: per-profile Continue Watching/resume,
  Who's-Watching + switching, and My List — all CloudKit-synced. Then: owner on-device DoD, and the
  `feat/profiles` merge decision.
