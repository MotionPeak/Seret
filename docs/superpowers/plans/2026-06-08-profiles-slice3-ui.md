# Profiles — Slice 3 (Who's-Watching + Profile Management UI) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make profiles visible and switchable — a "Who's Watching?" gate (only when >1 profile), profile create/delete, and a Switch-Profile action — driven by a shared `ActiveProfileStore`, with per-app native screens on tvOS and iOS.

**Architecture:** A new shared `ActiveProfileStore` (`@MainActor @Observable`, in DebridUI) owns the roster + the device-local active selection (`UserDefaults`) behind a `ProfileRosterProviding` seam over `ProfileStore` (unit-tested host-free). `AppSession` composes it, replaces the Slice-2 inline bootstrap with `loadAndResolve()`, exposes `activeProfileID` + `needsProfileSelection`, and re-injects + rebuilds Home on selection change. Each app gets a native `WhoIsWatching` screen + a Settings "Switch Profile" / "Manage Profiles" entry (design systems are per-app).

**Tech Stack:** Swift 6, SwiftUI, SwiftData (behind the seam), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-06-08-profiles-design.md` (Slice 5 — the profile UI). Builds on Slices 1–2 (`ProfileStore`/`MyListStore`, per-profile progress, `AppSession.activeProfileID`).

**Conventions:** TDD for the store/seam (host-free `swift test`); AppSession + SwiftUI is build-verified (sim/CloudKit can't be unit-tested here; screenshots owner-pending). Zero warnings.

---

## File Structure

| File | Responsibility |
|---|---|
| `Shared/DebridUI/Sources/DebridUI/Profiles/ProfileRosterProviding.swift` (new) | Sendable seam over `ProfileStore` |
| `Shared/DebridUI/Sources/DebridUI/Profiles/ActiveProfileStore.swift` (new) | roster + device-local active selection + resolve/select/create/delete |
| `Shared/DebridUI/Tests/DebridUITests/ActiveProfileStoreTests.swift` (new) | host-free tests with a fake provider |
| `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift` | compose store; replace inline bootstrap; `needsProfileSelection`; `selectProfile`/`switchProfile`/`createProfile`/`deleteProfile` |
| `Apps/SeretTV/Profiles/WhoIsWatchingScreen.swift` (new) | tvOS focus grid of profiles + Add |
| `Apps/SeretTV/Shell/RootView.swift` | gate `.signedIn` on `needsProfileSelection` |
| `Apps/SeretTV/Shell/SettingsView.swift` | Switch Profile + Manage Profiles rows |
| `Apps/SeretMobile/Profiles/WhoIsWatchingScreen.swift` (new) | iOS touch grid of profiles + Add |
| `Apps/SeretMobile/Shell/RootView.swift` | gate `.signedIn` on `needsProfileSelection` |
| `Apps/SeretMobile/Shell/SettingsView.swift` | Switch Profile + Manage Profiles rows |

---

## Task 1: `ProfileRosterProviding` seam + fake

**Files:**
- Create: `Shared/DebridUI/Sources/DebridUI/Profiles/ProfileRosterProviding.swift`
- Test: `Shared/DebridUI/Tests/DebridUITests/ActiveProfileStoreTests.swift` (new)

- [ ] **Step 1: Write the seam + the store conformance** — create `ProfileRosterProviding.swift`:

```swift
import DebridCore
import Foundation

/// Sendable seam over `ProfileStore` so `ActiveProfileStore` is testable host-free (no SwiftData).
public protocol ProfileRosterProviding: Sendable {
    func all() async throws -> [ProfileDTO]
    func ensureOwnerProfileAndMigrate(ownerName: String, colorTag: String) async throws -> ProfileDTO
    func create(name: String, colorTag: String) async throws -> ProfileDTO
    func rename(id: String, to name: String) async throws
    func delete(id: String) async throws
}

extension ProfileStore: ProfileRosterProviding {
    // `all()` / `rename(id:to:)` / `delete(id:)` satisfy the requirements directly. Provide the
    // no-default overloads for the two factory methods (the store's take injectable id/at).
    public func create(name: String, colorTag: String) async throws -> ProfileDTO {
        try await create(name: name, colorTag: colorTag, id: UUID().uuidString, at: Date())
    }
    public func ensureOwnerProfileAndMigrate(ownerName: String, colorTag: String) async throws -> ProfileDTO {
        try await ensureOwnerProfileAndMigrate(ownerName: ownerName, colorTag: colorTag,
                                               id: UUID().uuidString, at: Date())
    }
}
```

- [ ] **Step 2: Write the failing test scaffold + fake** — create `ActiveProfileStoreTests.swift`:

```swift
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
    let d = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    return d
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
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `swift test --package-path Shared/DebridUI --filter ActiveProfileStoreTests`
Expected: FAIL — `cannot find 'ActiveProfileStore'` in scope.

- [ ] **Step 4: Commit the seam** (the store lands in Task 2; commit the seam now so it compiles with the existing `ProfileStore`)

Run: `swift build --package-path Shared/DebridUI 2>&1 | grep -i error || echo ok`
Expected: `ok` (seam compiles; the test fails only because `ActiveProfileStore` doesn't exist yet).

```bash
git add Shared/DebridUI/Sources/DebridUI/Profiles/ProfileRosterProviding.swift
git commit -m "feat(ui): ProfileRosterProviding seam over ProfileStore"
```

---

## Task 2: `ActiveProfileStore`

**Files:**
- Create: `Shared/DebridUI/Sources/DebridUI/Profiles/ActiveProfileStore.swift`
- Test: `Shared/DebridUI/Tests/DebridUITests/ActiveProfileStoreTests.swift`

- [ ] **Step 1: Add the failing tests** — append inside `ActiveProfileStoreTests`:

```swift
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
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --package-path Shared/DebridUI --filter ActiveProfileStoreTests`
Expected: FAIL — `ActiveProfileStore` not found.

- [ ] **Step 3: Implement** — create `ActiveProfileStore.swift`:

```swift
import DebridCore
import Foundation
import Observation

/// Owns the profile roster and the **device-local** active selection (Netflix-style: the roster
/// syncs via CloudKit, the selection does not). Drives the "Who's Watching?" gate.
@MainActor
@Observable
public final class ActiveProfileStore {
    public private(set) var roster: [ProfileDTO] = []
    public private(set) var activeProfileID: String?

    private let provider: ProfileRosterProviding
    private let defaults: UserDefaults
    private static let key = "seret.activeProfileID"

    public init(provider: ProfileRosterProviding, defaults: UserDefaults = .standard) {
        self.provider = provider
        self.defaults = defaults
    }

    public var activeProfile: ProfileDTO? { roster.first { $0.id == activeProfileID } }

    /// Show "Who's Watching?" when there are multiple profiles and this device hasn't resolved one.
    public var needsSelection: Bool { roster.count > 1 && activeProfile == nil }

    /// Ensure an owner profile exists (migrating Phase-1 progress), load the roster, and resolve the
    /// device-stored selection. Solo/owner-only → auto-select (no gate); multiple with no valid
    /// stored selection → leave unselected to force the gate.
    public func loadAndResolve() async {
        let owner = try? await provider.ensureOwnerProfileAndMigrate(ownerName: "Me", colorTag: "gold")
        roster = (try? await provider.all()) ?? []
        let stored = defaults.string(forKey: Self.key)
        if let stored, roster.contains(where: { $0.id == stored }) {
            activeProfileID = stored
        } else if roster.count <= 1 {
            activeProfileID = roster.first?.id ?? owner?.id
            persist()
        } else {
            activeProfileID = nil
        }
    }

    public func select(_ id: String) {
        guard roster.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
        persist()
    }

    /// Deselect to re-show "Who's Watching?" (the Switch-Profile action).
    public func switchProfile() {
        activeProfileID = nil
        defaults.removeObject(forKey: Self.key)
    }

    public func create(name: String, colorTag: String) async {
        _ = try? await provider.create(name: name, colorTag: colorTag)
        roster = (try? await provider.all()) ?? roster
    }

    public func rename(id: String, to name: String) async {
        try? await provider.rename(id: id, to: name)
        roster = (try? await provider.all()) ?? roster
    }

    public func delete(id: String) async {
        try? await provider.delete(id: id)
        if activeProfileID == id { switchProfile() }
        roster = (try? await provider.all()) ?? roster
    }

    private func persist() {
        if let id = activeProfileID { defaults.set(id, forKey: Self.key) }
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --package-path Shared/DebridUI --filter ActiveProfileStoreTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Profiles/ActiveProfileStore.swift \
        Shared/DebridUI/Tests/DebridUITests/ActiveProfileStoreTests.swift
git commit -m "feat(ui): ActiveProfileStore — roster + device-local selection + Who's-Watching gate"
```

---

## Task 3: Wire `ActiveProfileStore` into `AppSession`

Replace the Slice-2 inline owner bootstrap with the store, and add selection actions that re-inject
into Home + rebuild.

**Files:**
- Modify: `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift`

- [ ] **Step 1: Add the property** — near `profileStore`:

```swift
    /// Device-local active-profile selection + roster (drives the Who's-Watching gate).
    public private(set) var activeProfiles: ActiveProfileStore?
```

- [ ] **Step 2: Make `activeProfileID` read from the store** — replace the stored
  `public private(set) var activeProfileID: String?` declaration with a computed property:

```swift
    /// The profile this device is watching as (nil until resolved / while the gate is showing).
    public var activeProfileID: String? { activeProfiles?.activeProfileID }
    /// True when the Who's-Watching gate should show (more than one profile, none chosen here).
    public var needsProfileSelection: Bool { activeProfiles?.needsSelection ?? false }
```

- [ ] **Step 3: Replace the inline bootstrap in `enterSignedIn()`** — swap the Slice-2 block:

```swift
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

with:

```swift
        if let profileStore {
            let profiles = ActiveProfileStore(provider: profileStore)
            activeProfiles = profiles
            Task { @MainActor in
                await profiles.loadAndResolve()
                self.home?.activeProfileID = profiles.activeProfileID
                await self.rebuildHome()
            }
        }
```

- [ ] **Step 4: Add selection actions** — add to `AppSession` (after `rebuildHome()`):

```swift
    /// Pick a profile (Who's-Watching tap): persist, re-scope Home, rebuild.
    public func selectProfile(_ id: String) {
        activeProfiles?.select(id)
        home?.activeProfileID = activeProfileID
        Task { await rebuildHome() }
    }

    /// Switch user — clears the device selection so the Who's-Watching gate reappears.
    public func switchProfile() {
        activeProfiles?.switchProfile()
        home?.activeProfileID = nil
    }

    /// Create a profile (then it can be picked on the Who's-Watching screen).
    public func createProfile(name: String, colorTag: String) async {
        await activeProfiles?.create(name: name, colorTag: colorTag)
    }

    /// Delete a profile (cascades its progress + My List via the store).
    public func deleteProfile(_ id: String) async {
        await activeProfiles?.delete(id: id)
        home?.activeProfileID = activeProfileID
        await rebuildHome()
    }
```

- [ ] **Step 5: Build + tests**

Run: `swift build --package-path Shared/DebridUI 2>&1 | grep -i warning || echo none` (none)
Run: `swift test --package-path Shared/DebridUI 2>&1 | tail -2` (green)
Expected: clean; `makePlayer` + DetailStore still read the computed `activeProfileID` (no call-site change).

- [ ] **Step 6: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift
git commit -m "feat(ui): AppSession drives profiles via ActiveProfileStore + select/switch/create/delete"
```

---

## Task 4: tvOS — Who's-Watching screen + gate + Settings actions

**Files:**
- Create: `Apps/SeretTV/Profiles/WhoIsWatchingScreen.swift`
- Modify: `Apps/SeretTV/Shell/RootView.swift`, `Apps/SeretTV/Shell/SettingsView.swift`

- [ ] **Step 1: Create the screen** — `WhoIsWatchingScreen.swift`. Read
  `Apps/SeretTV/DesignSystem/Theme.swift`, `Brand.swift`, `SeretPill.swift` first for the exact
  `Theme.Palette` members, `CanvasBackground`, `SeretMark`, and `SeretPillStyle` used by
  `HomeScreen`. Then build a focusable grid of profiles (monogram circle in the profile's color +
  name) plus an "Add Profile" tile; tapping a profile calls `session.selectProfile(id)`:

```swift
import DebridCore
import DebridUI
import SwiftUI

/// tvOS "Who's Watching?" — pick a profile (or add one). Shown by RootView when more than one
/// profile exists and this device hasn't resolved a selection.
struct WhoIsWatchingScreen: View {
    @Environment(AppSession.self) private var session
    @State private var addingName = ""
    @State private var showingAdd = false

    private var profiles: [ProfileDTO] { session.activeProfiles?.roster ?? [] }

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(spacing: 60) {
                Text("Who's Watching?")
                    .font(.system(size: 56, weight: .heavy))
                    .foregroundStyle(Theme.Palette.textPrimary)
                HStack(spacing: 50) {
                    ForEach(profiles) { p in
                        Button { session.selectProfile(p.id) } label: {
                            ProfileAvatar(profile: p)
                        }
                        .buttonStyle(.card)
                    }
                    Button { showingAdd = true } label: { AddProfileTile() }
                        .buttonStyle(.card)
                }
            }
        }
        .alert("New Profile", isPresented: $showingAdd) {
            TextField("Name", text: $addingName)
            Button("Create") {
                let name = addingName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task { await session.createProfile(name: name, colorTag: "gold"); addingName = "" }
            }
            Button("Cancel", role: .cancel) { addingName = "" }
        }
    }
}

/// Circular monogram avatar in the profile's color.
struct ProfileAvatar: View {
    let profile: ProfileDTO
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.Palette.color(for: profile.colorTag))
                    .frame(width: 200, height: 200)
                Text(String(profile.name.prefix(1)).uppercased())
                    .font(.system(size: 84, weight: .bold)).foregroundStyle(.black)
            }
            Text(profile.name).font(.title3).foregroundStyle(Theme.Palette.textPrimary)
        }
    }
}

struct AddProfileTile: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().strokeBorder(Theme.Palette.textSecondary, lineWidth: 3)
                    .frame(width: 200, height: 200)
                Image(systemName: "plus").font(.system(size: 72, weight: .bold))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Text("Add Profile").font(.title3).foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
```

> If `Theme.Palette` has no `color(for:)` mapper, add a small one to the tvOS `Theme.swift` mapping
> color tags ("gold", "blue", "green", "red", "purple") → `Color`, defaulting to `.gold`. Keep it in
> the design system, not the screen.

- [ ] **Step 2: Gate it in `RootView`** — change the `.signedIn` case:

```swift
            case .signedIn:
                if session.needsProfileSelection {
                    WhoIsWatchingScreen()
                } else {
                    LibraryShell()
                }
```

- [ ] **Step 3: Add Settings rows** — in `Apps/SeretTV/Shell/SettingsView.swift`, add a "Switch
  Profile" button (`session.switchProfile()`) and, if the active profile is known, show its name.
  Read the file first to match its existing row/section style; add:

```swift
            Button("Switch Profile") { session.switchProfile() }
```

  (Placed in a sensible section; styled like the existing Settings buttons.)

- [ ] **Step 4: Regenerate + build tvOS**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -4
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Apps/SeretTV/Profiles/WhoIsWatchingScreen.swift Apps/SeretTV/Shell/RootView.swift \
        Apps/SeretTV/Shell/SettingsView.swift Apps/SeretTV/DesignSystem/Theme.swift
git commit -m "feat(tvos): Who's-Watching gate + profile avatars + Switch Profile"
```

---

## Task 5: iOS — Who's-Watching screen + gate + Settings actions

**Files:**
- Create: `Apps/SeretMobile/Profiles/WhoIsWatchingScreen.swift`
- Modify: `Apps/SeretMobile/Shell/RootView.swift`, `Apps/SeretMobile/Shell/SettingsView.swift`

- [ ] **Step 1: Create the touch screen** — read `Apps/SeretMobile/DesignSystem/Theme.swift` +
  `SeretMark.swift` + `Modifiers.swift` first for the iOS palette/helpers. Build a touch grid
  (LazyVGrid, ~2–3 columns) of `ProfileAvatar`s (sized ~120pt for touch) + an Add tile; tap →
  `session.selectProfile(id)`; an alert with a `TextField` for "Add Profile" (same `createProfile`
  call as tvOS). Mirror the tvOS structure with iOS sizing and the mobile `Theme.Palette`.

```swift
import DebridCore
import DebridUI
import SwiftUI

struct WhoIsWatchingScreen: View {
    @Environment(AppSession.self) private var session
    @State private var addingName = ""
    @State private var showingAdd = false
    private var profiles: [ProfileDTO] { session.activeProfiles?.roster ?? [] }
    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 28)]

    var body: some View {
        ZStack {
            Theme.Palette.canvas.ignoresSafeArea()
            VStack(spacing: 40) {
                Text("Who's Watching?")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Theme.Palette.textPrimary)
                LazyVGrid(columns: columns, spacing: 28) {
                    ForEach(profiles) { p in
                        Button { session.selectProfile(p.id) } label: { ProfileAvatar(profile: p) }
                            .buttonStyle(.plain)
                    }
                    Button { showingAdd = true } label: { AddProfileTile() }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
            }
        }
        .alert("New Profile", isPresented: $showingAdd) {
            TextField("Name", text: $addingName)
            Button("Create") {
                let name = addingName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task { await session.createProfile(name: name, colorTag: "gold"); addingName = "" }
            }
            Button("Cancel", role: .cancel) { addingName = "" }
        }
    }
}

private struct ProfileAvatar: View {
    let profile: ProfileDTO
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.Palette.color(for: profile.colorTag)).frame(width: 110, height: 110)
                Text(String(profile.name.prefix(1)).uppercased())
                    .font(.system(size: 46, weight: .bold)).foregroundStyle(.black)
            }
            Text(profile.name).font(.headline).foregroundStyle(Theme.Palette.textPrimary)
        }
    }
}

private struct AddProfileTile: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().strokeBorder(Theme.Palette.textSecondary, lineWidth: 2).frame(width: 110, height: 110)
                Image(systemName: "plus").font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Text("Add").font(.headline).foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
```

> Add the same `Theme.Palette.color(for:)` mapper to the mobile `Theme.swift` if absent.

- [ ] **Step 2: Gate it in mobile `RootView`** — change the `.signedIn` case:

```swift
        case .signedIn:
            if session.needsProfileSelection {
                WhoIsWatchingScreen()
            } else {
                MainShell()
            }
```

- [ ] **Step 3: Add a Settings row** — in `Apps/SeretMobile/Shell/SettingsView.swift`, add a
  "Switch Profile" button calling `session.switchProfile()` (match the existing Form/section style;
  read the file first).

- [ ] **Step 4: Regenerate + build iOS**

Run:
```bash
xcodegen generate >/dev/null
xcodebuild -scheme SeretMobile -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -4
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Apps/SeretMobile/Profiles/WhoIsWatchingScreen.swift Apps/SeretMobile/Shell/RootView.swift \
        Apps/SeretMobile/Shell/SettingsView.swift Apps/SeretMobile/DesignSystem/Theme.swift
git commit -m "feat(ios): Who's-Watching gate + profile avatars + Switch Profile"
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

- **Owner-pending (sim/device):** the Who's-Watching flow's screenshots — create a 2nd profile,
  confirm the gate appears on next launch, pick a profile, confirm separate Continue Watching. The
  tvOS sim may need a Claude.app restart (pty issue); mobile sim needs the owner's RD token to pass
  sign-in first.
- Profile **rename + color picker** are intentionally minimal here (create + delete + switch is the
  MVP). A later polish pass can add a full manager screen if wanted — `ActiveProfileStore.rename`
  already exists.
- Keep the design-system `color(for:)` mapper in each app's `Theme.swift`, not in the screens.
- `WhoIsWatchingScreen` is per-app by design (tvOS focus vs iOS touch); both bind to the one shared
  `ActiveProfileStore` via `AppSession`.
