# Request Download — Slice 2 Completion Plan

> **For agentic workers:** Inline execution (executing-plans). Steps use `- [ ]`. The owner has
> already built the `DownloadStore` view-model + the iOS Add-flow Request Download; this plan
> fills the remaining gaps. Stage only the named paths — the owner edits in parallel.

**Goal:** Finish the user-facing "Request Download" feature: a non-playable title (Detail) and a
no-instant-version movie (tvOS Add) can start a background RD download; the library shows a
"downloading" badge; a local notification fires when it's ready; and cached vs uncached versions
are distinguishable.

**Already done (owner):** `DownloadStore` (`request/status/loadActive/refresh/poll`) wired in
`AppSession` as `session.downloadStore`; `AddStore.uncachedCandidates()` (fetches
`streams(for:includeUncached:true)` + `rankedFor`); iOS `AddScreen` DownloadSection.

**Branch:** `feat/stage2-search-add`. Spec: `docs/superpowers/specs/2026-06-07-request-download-uncached-design.md` (see Spike result).

---

## Task 1 (brain): `isCached` on `CachedStream`, parsed from the Comet marker

Comet labels each stream's `name`: `[RD⚡]…` = cached/instant, `[RD⬇️]…` = uncached/will-download
(confirmed by the spike). Surface this so the UI can show "Instant" vs "Will download" and the
picker can prefer an instant version.

**Files:** `Packages/DebridCore/Sources/DebridCore/Search/StreamModels.swift`,
`CometStreamSource.swift`; test `Packages/DebridCore/Tests/DebridCoreTests/CometCacheLabelTests.swift`.

- [ ] **Step 1: Failing test** — assert `map` sets `isCached` from the name marker.

```swift
import Testing
import Foundation
@testable import DebridCore

@Suite struct CometCacheLabelTests {
    @Test func parsesCachedAndUncachedMarkers() {
        #expect(CometStreamSource.isCachedName("[RD⚡] Comet 2160p") == true)
        #expect(CometStreamSource.isCachedName("[RD⬇️] Comet 1080p") == false)
        #expect(CometStreamSource.isCachedName("Comet 1080p") == false)   // no marker → not cached
    }
}
```

- [ ] **Step 2: Run** `cd Packages/DebridCore && swift test --filter CometCacheLabelTests` → FAIL.

- [ ] **Step 3:** Add `isCached` to `CachedStream` (in `StreamModels.swift`): a new `public let isCached: Bool`
  with a default in the memberwise `init` (`isCached: Bool = false`) so existing call sites/tests
  still compile. Add a static helper + set it in `CometStreamSource.map`:

```swift
// In CometStreamSource:
/// Comet flags cache state in the stream name: "⚡" = cached/instant, "⬇" = will-download.
static func isCachedName(_ name: String?) -> Bool {
    guard let name else { return false }
    return name.contains("⚡")
}
```
In `map(...)`, pass `isCached: Self.isCachedName(dto.name)` into the `CachedStream(...)` init.

- [ ] **Step 4: Run** the filter then the FULL suite (`swift test`) → all green.
- [ ] **Step 5: Commit**
```bash
git add Packages/DebridCore/Sources/DebridCore/Search/StreamModels.swift \
        Packages/DebridCore/Sources/DebridCore/Search/CometStreamSource.swift \
        Packages/DebridCore/Tests/DebridCoreTests/CometCacheLabelTests.swift
git commit -m "feat(core): parse Comet cache marker into CachedStream.isCached"
```

---

## Task 2 (DebridUI): `DetailStore.uncachedCandidates()`

So the Detail screen can fetch+rank candidates exactly like the Add flow.

**Files:** `Shared/DebridUI/Sources/DebridUI/Detail/DetailStore.swift`; the seam already exists
(`StreamSource`); test `Shared/DebridUI/Tests/DebridUITests/DetailStoreDownloadTests.swift`.

- [ ] **Step 1:** Read `DetailStore.swift` and `AddStore.uncachedCandidates()` to mirror the exact
  query construction (`StreamQuery(imdbID:kind:originalLanguage:title:year:)`, then
  `streamSource.streams(for: query, includeUncached: true).rankedFor(originalLanguage:)`).
  `DetailStore` must gain an injected `StreamSource?` (optional, default nil so existing
  constructions/tests compile) and a `func uncachedCandidates() async -> [CachedStream]` returning
  `[]` when no source/imdbID.
- [ ] **Step 2: Failing test** — a `DetailStore` with a fake `StreamSource` returning 2 streams;
  assert `uncachedCandidates()` returns them ranked; with no source → `[]`.
- [ ] **Step 3:** Run → FAIL. **Step 4:** Implement. **Step 5:** Run filter + full DebridUI suite.
- [ ] **Step 6:** Wire the new `streamSource` arg where `DetailStore(...)` is constructed
  (`AppSession.makeDetailStore`/the Detail screens). **Step 7: Commit** (stage DetailStore.swift,
  the new test, and the construction-site files).

---

## Task 3 (iOS + tvOS Detail UI): Request Download + live progress when not playable

When `store.bestSource == nil` (movie) or an episode/show has no playable source, render a
**Request Download** button instead of Play; once requested, render a status row from
`session.downloadStore?.status(forTMDB: item.tmdbID)` ("Queued…", "Downloading NN%", "Couldn't
start — Try another version"). Reuse the iOS `AddScreen` DownloadSection visual pattern.

**Files (iOS):** `Apps/SeretMobile/Detail/MovieDetail.swift`, `ShowDetail.swift`.
**Files (tvOS):** `Apps/SeretTV/Detail/MovieDetailView.swift`, `ShowDetailView.swift`.

- [ ] **Step 1:** Read the iOS `AddScreen` DownloadSection (the owner's working pattern) + each
  Detail `actions` block. Add a `@Environment(AppSession.self)` (already present in DetailScreen;
  Movie/ShowDetail take `store` — pass `downloadStore` + an `onRequest` closure down, or read the
  session env if available).
- [ ] **Step 2:** In the movie `actions`, add an `else` to `if let best = store.bestSource { … }`:
  when nil, show `RequestDownloadControl(tmdbID:title:kind:status:onRequest:)` — a small view that
  shows the button or the live progress row from `downloadStore.status(forTMDB:)`. The `onRequest`
  does `let c = await store.uncachedCandidates(); await session.downloadStore?.request(tmdbID:…, candidates: c)`.
- [ ] **Step 3:** Build each app (`xcodebuild -scheme SeretMobile … build`, `… SeretTV …`) → SUCCEEDED, 0 warnings.
- [ ] **Step 4: Commit** per app (stage only the Detail files you changed).

(No unit tests for SwiftUI views; verify by build + owner on-device. The request/progress logic is
already unit-tested in `DownloadStore`.)

---

## Task 4 (tvOS Add): uncached fallback for movies (parity with iOS)

iOS `AddScreen` shows a Request Download section when there are no instant streams; tvOS only
handles season-packs. Add the same movie fallback to tvOS.

**Files:** `Apps/SeretTV/Search/AddScreen.swift` (mirror `Apps/SeretMobile/Search/AddScreen.swift`'s `DownloadSection`).

- [ ] **Step 1:** Read both AddScreens. **Step 2:** Port the iOS DownloadSection (no-instant →
  Request Download → progress) into the tvOS AddScreen, using tvOS-focusable buttons.
  **Step 3:** Build tvOS → SUCCEEDED. **Step 4: Commit.**

---

## Task 5 (Library badge, both apps): "downloading" overlay on posters

Overlay a small progress badge on a poster when `session.downloadStore?.status(forTMDB: item.tmdbID)`
is non-nil. Clears automatically when the download completes (status removed) and the title becomes
a normal library item.

**Files (iOS):** `Apps/SeretMobile/Library/LibraryGrid.swift` (+ `MyLibraryScreen.swift` to pass the
store). **Files (tvOS):** `Apps/SeretTV/Library/PosterCard.swift`/`PosterGrid.swift`/`LibraryScreen.swift`/`MyLibraryScreen.swift`.

- [ ] **Step 1:** Thread `downloadStore` (or a `status(for:)->DownloadStatus?` closure) into the
  grids. **Step 2:** In each poster tile, `.overlay` a badge (a ⬇ glyph + `Int(fraction*100)%`, or a
  small `ProgressView`) when a status exists for `item.tmdbID`. **Step 3:** Build both apps → 0
  warnings. **Step 4: Commit** per app (stage only the library files).

---

## Task 6 (Notification): local notification when a download is ready

Fire a local notification ("<title> is ready to watch") when `DownloadStore.onReady` triggers,
while the app is active (foreground). Background polling is Slice 3 — out of scope.

**Files:** new `Shared/DebridUI/Sources/DebridUI/Downloads/DownloadNotifier.swift` (a tiny
`UserNotifications` wrapper, `@MainActor`); wire it in `AppSession`'s `onReady`.

- [ ] **Step 1:** Add `DownloadNotifier` with `requestAuthorization()` and
  `notifyReady(title:)` (builds `UNMutableNotificationContent`, `UNUserNotificationCenter.current().add(...)`
  with a nil trigger = immediate). Guard for unauthorized (no-op).
- [ ] **Step 2:** In `AppSession.enterSignedIn`, the `onReady` closure already calls
  `libraryStore?.retry()`; extend it to also resolve the title for the tmdbID (from the persisted
  record before it's cleared, or carry the title) and call `notifier.notifyReady(title:)`. Request
  authorization once at sign-in (or first request).
- [ ] **Step 3:** Build both apps → SUCCEEDED, 0 warnings. (Notification permission + delivery is
  owner-pending on-device — can't assert from the sim reliably.)
- [ ] **Step 4: Commit.**

---

## Order & verification

Build in order 1→6 (Task 2 depends on 1 only loosely; Tasks 3/5 depend on 2; 6 is independent).
After all: `cd Packages/DebridCore && swift test` + `cd Shared/DebridUI && swift test` green, both
apps `xcodebuild … build` 0-warning. On-device DoD (real uncached download → progress → ready →
Play + notification) is owner-pending, same pattern as the player.

## Out of scope (Slice 3)

Background `BGAppRefreshTask` polling + notification while the app is closed (iOS); tvOS best-effort.
