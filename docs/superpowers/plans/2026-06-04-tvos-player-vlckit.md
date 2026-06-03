# tvOS VLCKit Player (Plan 7c) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `PlayerPlaceholderView` with a real VLCKit-backed player that plays a Real-Debrid stream end-to-end on Apple TV (unrestrict → load → resume → play → save), with a minimal SwiftUI transport, track/audio menus, on-demand He/En OpenSubtitles, and buffering/error states.

**Architecture:** New code is app-side (`Apps/SeretTV`); the DebridCore brain (Plans 1–6) is reused unchanged except one new generic infra file (`SecretStore`). A thin `VLCKitVideoPlayerEngine` conforms to DebridCore's existing `VideoPlayerEngine` protocol and wraps `VLCMediaPlayer`. A `@MainActor @Observable` `PlayerModel` orchestrates one playback session against protocol/closure-typed dependencies (so it is fully unit-testable without VLCKit or the network). `PlayerView` is pure SwiftUI presented as a `.fullScreenCover`.

**Tech Stack:** Swift 6, SwiftUI (tvOS 18), TVVLCKit 3.6.0 (vendored xcframework, XcodeGen-embedded), Swift Testing, SwiftData (existing, untouched here), DebridCore local package.

**Reference:** Design spec at `docs/superpowers/specs/2026-06-04-tvos-player-vlckit-design.md`.

---

## Plan-time refinement of the spec

The spec (§4.2) said `PlayerModel` takes a `PlaybackCoordinator`. To keep `PlayerModel` unit-testable **without** spinning up a SwiftData `WatchProgressStore` (which would drag in the `@Suite(.serialized)` SwiftData hazard), `PlayerModel` instead takes a plain **`recordProgress: (Double, Double) async -> Void`** closure. `AppSession` builds the real `PlaybackCoordinator` from the concrete `WatchProgressStore` and passes `{ pos, dur in await coordinator.record(contentKey:, sourceKey:, position: pos, duration: dur) }` as that closure. Resume still comes from `request.resumeAt` directly. This is the only deviation from the spec; everything else matches.

## File structure

**New — DebridCore (one infra file + its tests):**
- `Packages/DebridCore/Sources/DebridCore/Persistence/SecretStore.swift` — `SecretStore` protocol + `KeychainSecretStore` + `InMemorySecretStore`.
- `Packages/DebridCore/Tests/DebridCoreTests/SecretStoreTests.swift` — contract tests against `InMemorySecretStore`.

**New — app target (`Apps/SeretTV`):**
- `Playback/VLCKitVideoPlayerEngine.swift` — `VideoPlayerEngine` conformer wrapping `VLCMediaPlayer`.
- `Playback/PlayerModel.swift` — orchestrator + `Phase` + `SubtitleRow`.
- `Playback/PlayerView.swift` — full-screen SwiftUI player shell.
- `Playback/VLCVideoView.swift` — `UIViewRepresentable` for the video surface.
- `Playback/PlayerOverlays.swift` — `TransportOverlay`, `LoadingOverlay`, `ErrorOverlay`.
- `Playback/TrackMenuPanel.swift` — Subtitles & Audio right-side panel.
- `Playback/SubtitleQuery+Item.swift` — build a `SubtitleQuery` from `MediaItem` / `(MediaItem, Episode)`.
- `Support/OpenSubtitlesAccount.swift` — `Codable` username/password + secret-store glue.
- `Shell/SettingsModel.swift` — `@Observable` save/load/clear of the OpenSubtitles account.

**New — app tests (`Apps/SeretTVTests`):**
- `Playback/Fakes.swift` — `FakeVideoPlayerEngine`, `FakeSubtitleProvider`.
- `Playback/PlayerModelTests.swift`
- `Shell/SettingsModelTests.swift`

**Modified:**
- `Scripts/fetch-frameworks.sh` — finalize the TVVLCKit pin.
- `project.yml` — embed `TVVLCKit.xcframework` in `SeretTV`.
- `Apps/SeretTV/Support/Secrets.swift` — add `openSubtitlesAPIKey`.
- `Secrets.xcconfig` + `Secrets.example.xcconfig` + `Apps/SeretTV/Info.plist` — add the key.
- `Apps/SeretTV/Shell/SettingsView.swift` — add the OpenSubtitles account section.
- `Apps/SeretTV/Shell/AppSession.swift` — vend playback + subtitle deps.
- `Apps/SeretTV/Shell/LibraryShell.swift:53` — present `PlayerView` via `.fullScreenCover`, removing `PlayerPlaceholderView`.

**Deleted:**
- `Apps/SeretTV/Playback/PlayerPlaceholderView.swift` — replaced (delete in Task 10).

---

## Task 1: Vendor TVVLCKit.xcframework + linkage smoke

**Files:**
- Modify: `Scripts/fetch-frameworks.sh`
- Modify: `project.yml` (the `SeretTV` target's `dependencies:`)
- Create: `Apps/SeretTV/Playback/VLCKitVideoPlayerEngine.swift` (stub — fleshed out in Task 2)

- [ ] **Step 1: Resolve the TVVLCKit 3.6.0 artifact**

The exact tarball URL + sha256 are not yet known. Resolve them (VideoLAN publishes the pods used by `MobileVLCKit`/`TVVLCKit`):

```bash
# Option A — read the CocoaPods podspec to get the http source for the version:
pod spec cat TVVLCKit | grep -A3 '"http"'        # shows the .tar.xz/.zip URL for 3.6.0
# Option B — browse the artifact index directly:
#   https://download.videolan.org/pub/cocoapods/prod/
# Pick the TVVLCKit-3.6.0-*.tar.xz that contains TVVLCKit.xcframework (xcframework build).
# Then compute the digest you will pin:
curl -fL "<resolved-url>" -o /tmp/tvvlckit.tar.xz
shasum -a 256 /tmp/tvvlckit.tar.xz               # copy this digest
```
Expected: a concrete `https://download.videolan.org/...` URL and a 64-hex sha256. If the only artifact is a non-xcframework "fat framework," prefer the xcframework build; if none exists for 3.6.0, use the nearest stable 3.x that ships an `xcframework` and update `VLCKIT_VERSION` accordingly.

- [ ] **Step 2: Finalize `Scripts/fetch-frameworks.sh`**

Set the two pins and enable the move. Replace the placeholder lines and the trailing guard:

```bash
VLCKIT_VERSION="3.6.0"          # match the resolved artifact
DEST_DIR="Frameworks"
PINNED_URL="<resolved-url-from-step-1>"
EXPECTED_SHA256="<digest-from-step-1>"
```
and replace the commented tail (the `# mv ...` block + the final `echo`/`exit 1` guard) with:
```bash
tar -xJf "$tmp/vlckit.tar.xz" -C "$tmp"
# The tarball roots at TVVLCKit.xcframework (verify with: tar -tJf … | head). Adjust if nested.
rm -rf "$DEST_DIR/TVVLCKit.xcframework"
mv "$tmp/TVVLCKit.xcframework" "$DEST_DIR/"
echo "Done: $DEST_DIR/TVVLCKit.xcframework"
```

- [ ] **Step 3: Run the fetch script**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && ./Scripts/fetch-frameworks.sh`
Expected: prints "Downloading TVVLCKit 3.6.0…", passes the `shasum -c` check, prints "Done: Frameworks/TVVLCKit.xcframework". Confirm: `ls Frameworks/TVVLCKit.xcframework/Info.plist` exists. (`Frameworks/` is already gitignored — do not commit the binary.)

- [ ] **Step 4: Embed the framework in `project.yml`**

In the `SeretTV` target, add a `dependencies:` entry alongside the existing `- package: DebridCore` (mirrors Nikud's `llama.xcframework`):

```yaml
  dependencies:
    - package: DebridCore
    - framework: Frameworks/TVVLCKit.xcframework
      embed: true
      codeSign: true
```
(The target already has `LD_RUNPATH_SEARCH_PATHS: [$(inherited), @executable_path/Frameworks]`, correct for a tvOS app bundle — leave it.)

- [ ] **Step 5: Create the engine stub to force linkage**

`Apps/SeretTV/Playback/VLCKitVideoPlayerEngine.swift`:
```swift
import UIKit
import TVVLCKit
import DebridCore

/// Adapter from VLCKit to DebridCore's `VideoPlayerEngine`. Fleshed out in Task 2.
@MainActor
final class VLCKitVideoPlayerEngine: NSObject {
    let videoView = UIView()
    private let player = VLCMediaPlayer()

    override init() {
        super.init()
        player.drawable = videoView
    }
}
```

- [ ] **Step 6: Regenerate the project and build**

Run:
```bash
cd /Users/shaharsolomons/Documents/Code/Seret && xcodegen generate \
  && xcodebuild -scheme SeretTV -destination 'generic/platform=tvOS Simulator' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`, zero warnings. This proves the xcframework links and `import TVVLCKit` resolves. (If launch is needed it requires a Claude.app restart per the pty-pool gotcha — build does not.)

- [ ] **Step 7: Commit**

```bash
git add Scripts/fetch-frameworks.sh project.yml Apps/SeretTV/Playback/VLCKitVideoPlayerEngine.swift
git commit -m "build(7c): vendor + embed TVVLCKit.xcframework"
```

---

## Task 2: Implement `VLCKitVideoPlayerEngine`

VLCKit-coupled, so it is verified by building + on-device playback (Task 9/10), not unit tests — the spec (§7) makes this explicit. Keep it thin.

**Files:**
- Modify: `Apps/SeretTV/Playback/VLCKitVideoPlayerEngine.swift`

- [ ] **Step 1: Implement the full adapter**

Replace the file body with:
```swift
import UIKit
import TVVLCKit
import DebridCore

@MainActor
final class VLCKitVideoPlayerEngine: NSObject, VideoPlayerEngine {
    let videoView = UIView()
    private let player = VLCMediaPlayer()
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    let events: AsyncStream<PlaybackEvent>

    override init() {
        var cont: AsyncStream<PlaybackEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { cont = $0 }
        continuation = cont
        super.init()
        player.drawable = videoView
        player.delegate = self
    }

    func load(url: URL, headers: [String: String]) {
        let media = VLCMedia(url: url)
        for (k, v) in headers { media.addOption(":http-\(k.lowercased())=\(v)") } // unused for RD CDN
        player.media = media
    }
    func play() { player.play() }
    func pause() { player.pause() }
    func seek(to seconds: Double) { player.time = VLCTime(int: Int32(seconds * 1000)) }

    // Track id == the VLCKit integer index rendered as a String.
    var audioTracks: [MediaTrack] { tracks(indexes: player.audioTrackIndexes,
                                           names: player.audioTrackNames, kind: .audio) }
    var subtitleTracks: [MediaTrack] { tracks(indexes: player.videoSubTitlesIndexes,
                                              names: player.videoSubTitlesNames, kind: .subtitle) }

    func selectAudioTrack(id: String?) { player.currentAudioTrackIndex = Int32(id ?? "") ?? -1 }
    func selectSubtitleTrack(id: String?) { player.currentVideoSubTitleIndex = Int32(id ?? "") ?? -1 }

    func addExternalSubtitle(url: URL) {
        player.addPlaybackSlave(url, type: .subtitle, enforce: true)
    }

    private func tracks(indexes: [Any], names: [Any], kind: TrackKind) -> [MediaTrack] {
        zip(indexes, names).compactMap { idx, name in
            guard let i = (idx as? NSNumber)?.intValue, i >= 0 else { return nil } // -1 == "Disable"
            let label = (name as? String) ?? "Track \(i)"
            return MediaTrack(id: String(i), kind: kind, name: label, language: nil)
        }
    }
}

extension VLCKitVideoPlayerEngine: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        switch player.state {
        case .opening, .buffering, .esAdded: continuation.yield(.state(.buffering))
        case .playing:                       continuation.yield(.state(.playing))
        case .paused:                        continuation.yield(.state(.paused))
        case .stopped, .ended:               continuation.yield(.state(.ended))
        case .error:                         continuation.yield(.state(.failed("Playback failed.")))
        @unknown default:                    break
        }
    }
    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        let position = Double(player.time.intValue) / 1000.0
        let duration = Double(player.media?.length.intValue ?? 0) / 1000.0
        continuation.yield(.time(PlaybackTime(position: position, duration: duration)))
    }
}
```

> **Verify-at-implement note:** confirm these selector/enum names against the vendored 3.6.0 headers — `audioTrackIndexes`/`audioTrackNames`/`currentAudioTrackIndex`, `videoSubTitlesIndexes`/`videoSubTitlesNames`/`currentVideoSubTitleIndex`, `addPlaybackSlave(_:type:enforce:)`, and `VLCMediaPlayerState` cases. If a name differs, adjust here only; the protocol and `PlayerModel` are unaffected.

- [ ] **Step 2: Build**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && xcodebuild -scheme SeretTV -destination 'generic/platform=tvOS Simulator' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`, zero warnings.

- [ ] **Step 3: Commit**

```bash
git add Apps/SeretTV/Playback/VLCKitVideoPlayerEngine.swift
git commit -m "feat(7c): VLCKitVideoPlayerEngine adapter over VLCMediaPlayer"
```

---

## Task 3: `SecretStore` in DebridCore (TDD)

A generic Keychain-backed secret store for the OpenSubtitles login. `InMemorySecretStore` makes consumers testable; `KeychainSecretStore` is thin and device-verified.

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Persistence/SecretStore.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/SecretStoreTests.swift`

- [ ] **Step 1: Write the failing test**

`SecretStoreTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

@Suite struct SecretStoreTests {
    @Test func inMemoryRoundTripsAndClears() throws {
        let store: SecretStore = InMemorySecretStore()
        #expect(try store.read() == nil)

        let payload = Data("hello".utf8)
        try store.write(payload)
        #expect(try store.read() == payload)

        try store.clear()
        #expect(try store.read() == nil)
    }

    @Test func writeOverwritesPreviousValue() throws {
        let store: SecretStore = InMemorySecretStore()
        try store.write(Data("one".utf8))
        try store.write(Data("two".utf8))
        #expect(try store.read() == Data("two".utf8))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret/Packages/DebridCore && swift test --filter SecretStoreTests 2>&1 | tail -15`
Expected: FAIL — `cannot find 'SecretStore'`/`'InMemorySecretStore'` in scope.

- [ ] **Step 3: Implement `SecretStore.swift`**

```swift
import Foundation

/// Stores a single opaque secret blob. Implementations key it however they like.
public protocol SecretStore: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func clear() throws
}

/// Keychain-backed generic-password store, keyed by `service` + `account`.
/// Mirrors `KeychainTokenStore`; verified on device (Keychain needs a host app).
public struct KeychainSecretStore: SecretStore {
    private let service: String
    private let account: String

    public init(service: String, account: String = "default") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func read() throws -> Data? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        return out as? Data
    }

    public func write(_ data: Data) throws {
        try clear()
        var q = baseQuery
        q[kSecValueData as String] = data
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    enum KeychainError: Error { case status(OSStatus) }
}

/// In-memory store for tests and previews.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Data?
    public init() {}
    public func read() throws -> Data? { lock.withLock { value } }
    public func write(_ data: Data) throws { lock.withLock { value = data } }
    public func clear() throws { lock.withLock { value = nil } }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret/Packages/DebridCore && swift test --filter SecretStoreTests 2>&1 | tail -8`
Expected: PASS (2 tests). Then run the full package to confirm nothing regressed: `swift test 2>&1 | tail -5` → all green (was 122).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Persistence/SecretStore.swift \
        Packages/DebridCore/Tests/DebridCoreTests/SecretStoreTests.swift
git commit -m "feat(7c): generic SecretStore (Keychain + in-memory) in DebridCore"
```

---

## Task 4: `Secrets.openSubtitlesAPIKey`

Mirror the existing `tmdbAPIKey` chain. No unit test (matches the TMDB key pattern).

**Files:**
- Modify: `Secrets.xcconfig`, `Secrets.example.xcconfig`, `Apps/SeretTV/Info.plist`, `Apps/SeretTV/Support/Secrets.swift`

- [ ] **Step 1: Add the build-time variable**

Append to `Secrets.xcconfig` (gitignored) and to `Secrets.example.xcconfig` (committed template, with an empty value + comment):
```xcconfig
// OpenSubtitles consumer API key (https://www.opensubtitles.com/en/consumers) — used by OpenSubtitlesProvider.
OPENSUBTITLES_API_KEY = <your_opensubtitles_api_key>
```
(In `Secrets.example.xcconfig` leave the value blank after `=`.)

- [ ] **Step 2: Inject into Info.plist**

Add under the existing keys in `Apps/SeretTV/Info.plist`:
```xml
<key>OpenSubtitlesAPIKey</key>
<string>$(OPENSUBTITLES_API_KEY)</string>
```

- [ ] **Step 3: Add the accessor**

In `Apps/SeretTV/Support/Secrets.swift`, add alongside `tmdbAPIKey`:
```swift
    /// OpenSubtitles API key: `OPENSUBTITLES_API_KEY` (Secrets.xcconfig) → `OpenSubtitlesAPIKey` (Info.plist) → here.
    /// Empty string when unset — callers treat empty as "subtitles unavailable."
    static var openSubtitlesAPIKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "OpenSubtitlesAPIKey") as? String) ?? ""
    }
```
(No `assert` — unlike TMDB, an absent key just disables subtitles rather than breaking the app.)

- [ ] **Step 4: Build**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && xcodegen generate && xcodebuild -scheme SeretTV -destination 'generic/platform=tvOS Simulator' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Secrets.example.xcconfig Apps/SeretTV/Info.plist Apps/SeretTV/Support/Secrets.swift
git commit -m "feat(7c): Secrets.openSubtitlesAPIKey (xcconfig → Info.plist → accessor)"
```
(Do not `git add Secrets.xcconfig` — it is gitignored.)

---

## Task 5: OpenSubtitles account — model + Settings form (TDD the model)

`SettingsModel` holds the save/load/clear logic and is unit-tested against `InMemorySecretStore`; `SettingsView` is a thin SwiftUI form over it (device-verified).

**Files:**
- Create: `Apps/SeretTV/Support/OpenSubtitlesAccount.swift`
- Create: `Apps/SeretTV/Shell/SettingsModel.swift`
- Modify: `Apps/SeretTV/Shell/SettingsView.swift`
- Test: `Apps/SeretTVTests/Shell/SettingsModelTests.swift`

- [ ] **Step 1: Create the codable account + store glue**

`Apps/SeretTV/Support/OpenSubtitlesAccount.swift`:
```swift
import Foundation
import DebridCore

struct OpenSubtitlesAccount: Codable, Equatable {
    var username: String
    var password: String
}

extension SecretStore {
    func readAccount() -> OpenSubtitlesAccount? {
        guard let data = try? read(), let data else { return nil }
        return try? JSONDecoder().decode(OpenSubtitlesAccount.self, from: data)
    }
    func writeAccount(_ account: OpenSubtitlesAccount) throws {
        try write(JSONEncoder().encode(account))
    }
}

extension OpenSubtitlesAccount {
    var credentials: OpenSubtitlesProvider.Credentials {
        .init(username: username, password: password)
    }
}
```

- [ ] **Step 2: Write the failing `SettingsModel` test**

`Apps/SeretTVTests/Shell/SettingsModelTests.swift`:
```swift
import Testing
@testable import Seret
import DebridCore

@MainActor
@Suite struct SettingsModelTests {
    @Test func savesAndReportsConnected() throws {
        let store = InMemorySecretStore()
        let model = SettingsModel(secretStore: store)
        #expect(model.isConnected == false)

        model.username = "neo"
        model.password = "trinity"
        model.save()

        #expect(model.isConnected == true)
        #expect(store.readAccount() == OpenSubtitlesAccount(username: "neo", password: "trinity"))
    }

    @Test func removeClearsCredentials() throws {
        let store = InMemorySecretStore()
        try store.writeAccount(.init(username: "neo", password: "trinity"))
        let model = SettingsModel(secretStore: store)
        #expect(model.isConnected == true)

        model.remove()
        #expect(model.isConnected == false)
        #expect(store.readAccount() == nil)
    }

    @Test func blankUsernameOrPasswordDoesNotSave() {
        let store = InMemorySecretStore()
        let model = SettingsModel(secretStore: store)
        model.username = "  "
        model.password = ""
        model.save()
        #expect(model.isConnected == false)
        #expect(store.readAccount() == nil)
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && xcodebuild test -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' -only-testing:SeretTVTests/SettingsModelTests 2>&1 | tail -15`
Expected: FAIL — `cannot find 'SettingsModel'`. (If the sim won't launch with the pty-pool error, restart Claude.app first — see the spec's verification note.)

- [ ] **Step 4: Implement `SettingsModel`**

`Apps/SeretTV/Shell/SettingsModel.swift`:
```swift
import Observation
import DebridCore

@MainActor
@Observable
final class SettingsModel {
    var username: String = ""
    var password: String = ""
    private(set) var isConnected: Bool

    private let secretStore: SecretStore

    init(secretStore: SecretStore) {
        self.secretStore = secretStore
        if let account = secretStore.readAccount() {
            username = account.username
            isConnected = true
        } else {
            isConnected = false
        }
    }

    func save() {
        let u = username.trimmingCharacters(in: .whitespaces)
        let p = password
        guard !u.isEmpty, !p.isEmpty else { return }
        try? secretStore.writeAccount(.init(username: u, password: p))
        isConnected = secretStore.readAccount() != nil
    }

    func remove() {
        try? secretStore.clear()
        password = ""
        isConnected = false
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && xcodebuild test -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' -only-testing:SeretTVTests/SettingsModelTests 2>&1 | tail -10`
Expected: PASS (3 tests).

- [ ] **Step 6: Add the Settings form**

In `Apps/SeretTV/Shell/SettingsView.swift`, add an OpenSubtitles section. Build a `SettingsModel` with a `KeychainSecretStore(service: "com.solomons.seret.opensubtitles")`. Replace the body with:
```swift
import SwiftUI
import DebridCore

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var model = SettingsModel(
        secretStore: KeychainSecretStore(service: "com.solomons.seret.opensubtitles"))

    var body: some View {
        VStack(spacing: 40) {
            Text("Settings").font(.largeTitle.bold())
            Text("Signed in to Real-Debrid.").font(.title3).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                Label("OpenSubtitles account", systemImage: "captions.bubble")
                    .font(.title3.bold())
                Text(model.isConnected
                     ? "Connected as \(model.username). Used to download Hebrew/English subtitles."
                     : "Add your free OpenSubtitles account to download subtitles during playback.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("Username", text: $model.username)
                    .textContentType(.username)
                SecureField("Password", text: $model.password)
                    .textContentType(.password)
                HStack(spacing: 20) {
                    Button("Save") { model.save() }
                    if model.isConnected {
                        Button("Remove", role: .destructive) { model.remove() }
                    }
                }
            }
            .frame(maxWidth: 700)

            Button(role: .destructive) {
                Task { await session.signOut() }
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right").font(.title3)
            }
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Settings")
    }
}
```

- [ ] **Step 7: Build, then commit**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && xcodebuild -scheme SeretTV -destination 'generic/platform=tvOS Simulator' build 2>&1 | tail -5` → `** BUILD SUCCEEDED **`.
```bash
git add Apps/SeretTV/Support/OpenSubtitlesAccount.swift Apps/SeretTV/Shell/SettingsModel.swift \
        Apps/SeretTV/Shell/SettingsView.swift Apps/SeretTVTests/Shell/SettingsModelTests.swift
git commit -m "feat(7c): OpenSubtitles account settings form + tested SettingsModel"
```

---

## Task 6: `PlayerModel` core — prepare → load → resume → play (TDD)

**Files:**
- Create: `Apps/SeretTV/Playback/PlayerModel.swift`
- Create: `Apps/SeretTVTests/Playback/Fakes.swift`
- Test: `Apps/SeretTVTests/Playback/PlayerModelTests.swift`

- [ ] **Step 1: Create the fakes**

`Apps/SeretTVTests/Playback/Fakes.swift`:
```swift
import Foundation
@testable import Seret
import DebridCore

@MainActor
final class FakeVideoPlayerEngine: VideoPlayerEngine {
    private(set) var loadedURL: URL?
    private(set) var seekedTo: Double?
    private(set) var playCalled = false
    private(set) var addedSubtitles: [URL] = []
    private(set) var selectedSubtitleID: String??

    var audioTracks: [MediaTrack] = []
    var subtitleTracks: [MediaTrack] = []

    let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    init() {
        var c: AsyncStream<PlaybackEvent>.Continuation!
        events = AsyncStream { c = $0 }
        continuation = c
    }
    /// Drive the model from a test.
    func emit(_ e: PlaybackEvent) { continuation.yield(e) }

    func load(url: URL, headers: [String: String]) { loadedURL = url }
    func play() { playCalled = true }
    func pause() {}
    func seek(to seconds: Double) { seekedTo = seconds }
    func selectAudioTrack(id: String?) {}
    func selectSubtitleTrack(id: String?) { selectedSubtitleID = id }
    func addExternalSubtitle(url: URL) { addedSubtitles.append(url) }
}

final class FakeSubtitleProvider: SubtitleProvider, @unchecked Sendable {
    var searchResults: [SubtitleResult] = []
    var searchError: Error?
    var downloadError: Error?
    var downloadedURL = URL(fileURLWithPath: "/tmp/sub.srt")
    private(set) var searchedLanguages: [[String]] = []

    func search(_ query: SubtitleQuery, languages: [String]) async throws -> [SubtitleResult] {
        searchedLanguages.append(languages)
        if let searchError { throw searchError }
        return searchResults
    }
    func download(_ result: SubtitleResult) async throws -> URL {
        if let downloadError { throw downloadError }
        return downloadedURL
    }
}

// Shared fixtures.
@MainActor
enum Fixture {
    static func movieSource(_ link: String = "rd://link") -> MediaSource {
        MediaSource(torrentID: "t1", fileID: nil, restrictedLink: link,
                    parsed: ParsedRelease(title: "Dune", year: 2024))   // adjust to ParsedRelease's real init
    }
    static func movie(sources: [MediaSource]) -> MediaItem {
        MediaItem(id: "m1", kind: .movie, title: "Dune: Part Two", year: 2024,
                  sources: sources, seasons: [], tmdbID: 693134,
                  posterPath: nil, backdropPath: nil, overview: nil)     // adjust to MediaItem's real init
    }
    static func request(resumeAt: Double? = nil, sources: [MediaSource]? = nil) -> PlaybackRequest {
        let srcs = sources ?? [movieSource()]
        return PlaybackRequest(item: movie(sources: srcs), source: srcs[0],
                               resumeAt: resumeAt, label: "Dune: Part Two")
    }
}
```
> The `ParsedRelease`/`MediaItem` initializers above are illustrative — at implement time, open `MediaItem.swift`/`FilenameParser.swift` and use their real memberwise inits / a test helper. Keep fixtures minimal.

- [ ] **Step 2: Write the failing core test**

`Apps/SeretTVTests/Playback/PlayerModelTests.swift`:
```swift
import Testing
import Foundation
@testable import Seret
import DebridCore

@MainActor
@Suite struct PlayerModelTests {
    private func makeModel(request: PlaybackRequest,
                           engine: FakeVideoPlayerEngine,
                           unrestrict: @escaping (String) async throws -> URL = { _ in URL(string: "https://cdn/x.mkv")! },
                           subtitles: SubtitleProvider? = nil,
                           recorded: @escaping (Double, Double) async -> Void = { _, _ in }) -> PlayerModel {
        PlayerModel(request: request, engine: engine, unrestrict: unrestrict,
                    recordProgress: recorded, subtitles: subtitles)
    }

    @Test func startUnrestrictsLoadsAndPlays() async {
        let engine = FakeVideoPlayerEngine()
        var unrestrictedLink: String?
        let model = makeModel(request: Fixture.request(),
                              engine: engine,
                              unrestrict: { link in unrestrictedLink = link; return URL(string: "https://cdn/x.mkv")! })
        model.start()
        await model.waitForIdleForTesting()

        #expect(unrestrictedLink == "rd://link")
        #expect(engine.loadedURL == URL(string: "https://cdn/x.mkv"))
        #expect(engine.playCalled == true)
        #expect(engine.seekedTo == nil)            // no resume requested
    }

    @Test func seeksToResumePositionWhenProvided() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(resumeAt: 615), engine: engine)
        model.start()
        await model.waitForIdleForTesting()
        #expect(engine.seekedTo == 615)
    }

    @Test func mapsEngineStatesToPhase() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine)
        model.start()
        await model.waitForIdleForTesting()

        engine.emit(.state(.buffering)); await model.waitForIdleForTesting()
        #expect(model.phase == .buffering)
        engine.emit(.state(.playing));   await model.waitForIdleForTesting()
        #expect(model.phase == .playing)
        engine.emit(.state(.paused));    await model.waitForIdleForTesting()
        #expect(model.phase == .paused)
    }

    @Test func unrestrictFailureSurfacesFailedPhase() async {
        struct Boom: Error {}
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(request: Fixture.request(), engine: engine,
                              unrestrict: { _ in throw Boom() })
        model.start()
        await model.waitForIdleForTesting()
        guard case .failed = model.phase else { Issue.record("expected .failed, got \(model.phase)"); return }
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && xcodebuild test -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' -only-testing:SeretTVTests/PlayerModelTests 2>&1 | tail -15`
Expected: FAIL — `cannot find 'PlayerModel'`.

- [ ] **Step 4: Implement `PlayerModel` core**

`Apps/SeretTV/Playback/PlayerModel.swift`:
```swift
import Observation
import Foundation
import DebridCore

@MainActor
@Observable
final class PlayerModel {
    enum Phase: Equatable { case preparing, buffering, playing, paused, ended, failed(String) }

    enum SubtitleRowState: Equatable { case idle, downloading, attached(String), capReached(Date?), error, noAccount }
    struct SubtitleRow: Identifiable, Equatable { let language: String; var state: SubtitleRowState; var id: String { language } }

    // Published UI state
    private(set) var phase: Phase = .preparing
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    var controlsVisible: Bool = true
    private(set) var audioTracks: [MediaTrack] = []
    private(set) var subtitleTracks: [MediaTrack] = []
    private(set) var subtitleRows: [SubtitleRow]
    private(set) var shouldDismiss: Bool = false

    // Dependencies
    private let item: MediaItem
    private let sources: [MediaSource]
    private var sourceIndex: Int = 0
    private let resumeAt: Double?
    let label: String
    private let engine: VideoPlayerEngine
    private let unrestrict: (String) async throws -> URL
    private let recordProgress: (Double, Double) async -> Void
    private let subtitles: SubtitleProvider?

    private let languages = ["he", "en"]
    private var eventTask: Task<Void, Never>?
    private var lastSavedPosition: Double = -.infinity
    private let saveInterval: Double = 5

    var canTryAnotherVersion: Bool { sources.count > 1 }
    var currentSource: MediaSource { sources[sourceIndex] }

    init(request: PlaybackRequest,
         engine: VideoPlayerEngine,
         unrestrict: @escaping (String) async throws -> URL,
         recordProgress: @escaping (Double, Double) async -> Void,
         subtitles: SubtitleProvider?) {
        self.item = request.item
        // Play the requested source first, then the remaining ranked alternatives.
        self.sources = [request.source] + request.item.sources.bestFirst().filter { $0 != request.source }
        self.resumeAt = request.resumeAt
        self.label = request.label
        self.engine = engine
        self.unrestrict = unrestrict
        self.recordProgress = recordProgress
        self.subtitles = subtitles
        let initial: SubtitleRowState = subtitles == nil ? .noAccount : .idle
        self.subtitleRows = ["he", "en"].map { SubtitleRow(language: $0, state: initial) }
    }

    func start() {
        phase = .preparing
        lastSavedPosition = -.infinity
        eventTask?.cancel()
        eventTask = Task { await self.run() }
    }

    private func run() async {
        do {
            let url = try await unrestrict(currentSource.restrictedLink)
            engine.load(url: url, headers: [:])
            if let resumeAt, resumeAt > 0 { engine.seek(to: resumeAt) }
            engine.play()
            for await event in engine.events {
                switch event {
                case .state(let s): handle(state: s)
                case .time(let t): await tick(t)
                }
            }
        } catch {
            phase = .failed("The Real-Debrid link could not be opened.")
        }
    }

    private func handle(state: PlaybackState) {
        switch state {
        case .idle, .buffering: phase = .buffering
        case .playing:
            phase = .playing
            audioTracks = engine.audioTracks
            subtitleTracks = engine.subtitleTracks
        case .paused: phase = .paused
        case .ended: Task { await finish() }
        case .failed(let reason): phase = .failed(reason)
        }
    }

    private func tick(_ t: PlaybackTime) async {
        position = t.position
        duration = t.duration
        if position - lastSavedPosition >= saveInterval {
            lastSavedPosition = position
            await recordProgress(position, duration)
        }
    }

    func togglePlayPause() {
        if phase == .playing { engine.pause() } else { engine.play() }
    }
    func skip(_ delta: Double) { engine.seek(to: max(0, position + delta)) }
    func scrub(to seconds: Double) { engine.seek(to: seconds) }

    private func finish() async {
        await recordProgress(position, duration)
        phase = .ended
        shouldDismiss = true
    }

    /// Persist final progress when the view is dismissed by the user.
    func teardown() async {
        eventTask?.cancel()
        await recordProgress(position, duration)
    }

    // Test hook: yield the main actor so queued continuation work runs.
    func waitForIdleForTesting() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && xcodebuild test -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' -only-testing:SeretTVTests/PlayerModelTests 2>&1 | tail -10`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add Apps/SeretTV/Playback/PlayerModel.swift Apps/SeretTVTests/Playback/Fakes.swift \
        Apps/SeretTVTests/Playback/PlayerModelTests.swift
git commit -m "feat(7c): PlayerModel core (prepare/load/resume/play + state mapping)"
```

---

## Task 7: `PlayerModel` — progress save cadence + end-of-playback (TDD)

**Files:**
- Modify: `Apps/SeretTV/Playback/PlayerModel.swift` (logic already present from Task 6 — this task adds tests that lock the behavior; extend logic only if a test fails)
- Test: `Apps/SeretTVTests/Playback/PlayerModelTests.swift`

- [ ] **Step 1: Write the failing save-cadence tests**

Append to `PlayerModelTests.swift`:
```swift
    @Test func savesAtMostEveryFiveSeconds() async {
        let engine = FakeVideoPlayerEngine()
        var saves: [(Double, Double)] = []
        let model = makeModel(request: Fixture.request(), engine: engine,
                              recorded: { p, d in saves.append((p, d)) })
        model.start(); await model.waitForIdleForTesting()

        engine.emit(.time(.init(position: 1, duration: 100))); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 3, duration: 100))); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 6, duration: 100))); await model.waitForIdleForTesting()

        // 1s → first save (gap from -inf); 3s → skip (<5s since 1); 6s → save (>=5s since 1).
        #expect(saves.map(\.0) == [1, 6])
    }

    @Test func endedSavesFinalAndRequestsDismiss() async {
        let engine = FakeVideoPlayerEngine()
        var saves: [(Double, Double)] = []
        let model = makeModel(request: Fixture.request(), engine: engine,
                              recorded: { p, d in saves.append((p, d)) })
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 95, duration: 100))); await model.waitForIdleForTesting()
        engine.emit(.state(.ended)); await model.waitForIdleForTesting()

        #expect(model.phase == .ended)
        #expect(model.shouldDismiss == true)
        #expect(saves.last?.0 == 95)            // final save at end
    }

    @Test func teardownPersistsCurrentPosition() async {
        let engine = FakeVideoPlayerEngine()
        var saves: [(Double, Double)] = []
        let model = makeModel(request: Fixture.request(), engine: engine,
                              recorded: { p, d in saves.append((p, d)) })
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: 42, duration: 100))); await model.waitForIdleForTesting()
        await model.teardown()
        #expect(saves.last?.0 == 42)
    }
```

- [ ] **Step 2: Run to verify (expect pass — logic shipped in Task 6)**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && xcodebuild test -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' -only-testing:SeretTVTests/PlayerModelTests 2>&1 | tail -10`
Expected: PASS (7 tests total). If `savesAtMostEveryFiveSeconds` fails, verify the `position - lastSavedPosition >= saveInterval` guard and that `lastSavedPosition` resets to `-.infinity` in `start()`.

- [ ] **Step 3: Commit**

```bash
git add Apps/SeretTVTests/Playback/PlayerModelTests.swift Apps/SeretTV/Playback/PlayerModel.swift
git commit -m "test(7c): lock PlayerModel save cadence + end-of-playback behavior"
```

---

## Task 8: `PlayerModel` — on-demand subtitles + retry / try-another-version (TDD)

**Files:**
- Modify: `Apps/SeretTV/Playback/PlayerModel.swift`
- Create: `Apps/SeretTV/Playback/SubtitleQuery+Item.swift`
- Test: `Apps/SeretTVTests/Playback/PlayerModelTests.swift`

- [ ] **Step 1: Write the failing subtitle + recovery tests**

Append to `PlayerModelTests.swift`:
```swift
    @Test func requestSubtitleDownloadsAttachesAndSelects() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 7, language: "he", release: nil, fileName: "he.srt", downloadCount: 1)]
        subs.downloadedURL = URL(fileURLWithPath: "/tmp/he.srt")
        let model = makeModel(request: Fixture.request(), engine: engine, subtitles: subs)
        model.start(); await model.waitForIdleForTesting()

        await model.requestSubtitle(language: "he")

        #expect(subs.searchedLanguages.last == ["he"])
        #expect(engine.addedSubtitles == [URL(fileURLWithPath: "/tmp/he.srt")])
        if case .attached = model.subtitleRows.first(where: { $0.language == "he" })?.state {} else {
            Issue.record("expected he row .attached, got \(String(describing: model.subtitleRows))")
        }
    }

    @Test func dailyCapMapsToCapReachedRow() async {
        let engine = FakeVideoPlayerEngine()
        let subs = FakeSubtitleProvider()
        subs.downloadError = SubtitleError.dailyCapReached(resetTime: nil)
        subs.searchResults = [SubtitleResult(fileID: 7, language: "he", release: nil, fileName: nil, downloadCount: nil)]
        let model = makeModel(request: Fixture.request(), engine: engine, subtitles: subs)
        model.start(); await model.waitForIdleForTesting()

        await model.requestSubtitle(language: "he")
        #expect(model.subtitleRows.first(where: { $0.language == "he" })?.state == .capReached(nil))
    }

    @Test func noProviderLeavesRowsNoAccount() async {
        let model = makeModel(request: Fixture.request(), engine: FakeVideoPlayerEngine(), subtitles: nil)
        #expect(model.subtitleRows.allSatisfy { $0.state == .noAccount })
    }

    @Test func tryAnotherVersionAdvancesToNextSource() async {
        let s1 = Fixture.movieSource("rd://one")
        let s2 = Fixture.movieSource("rd://two")
        let engine = FakeVideoPlayerEngine()
        var unrestricted: [String] = []
        let model = makeModel(request: Fixture.request(sources: [s1, s2]), engine: engine,
                              unrestrict: { link in unrestricted.append(link); return URL(string: "https://cdn/x.mkv")! })
        model.start(); await model.waitForIdleForTesting()
        engine.emit(.state(.failed("boom"))); await model.waitForIdleForTesting()
        #expect(model.canTryAnotherVersion == true)

        model.tryAnotherVersion(); await model.waitForIdleForTesting()
        #expect(unrestricted == ["rd://one", "rd://two"])
    }
```
> `s1`/`s2` differ only by link; `bestFirst()` keeps both. The constructed `sources` array is `[requested] + rankedOthers`, so index 1 is the other source.

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && xcodebuild test -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' -only-testing:SeretTVTests/PlayerModelTests 2>&1 | tail -15`
Expected: FAIL — `value of type 'PlayerModel' has no member 'requestSubtitle'`.

- [ ] **Step 3: Add the `SubtitleQuery` builder**

`Apps/SeretTV/Playback/SubtitleQuery+Item.swift`:
```swift
import DebridCore

extension SubtitleQuery {
    static func forMovie(_ item: MediaItem) -> SubtitleQuery {
        SubtitleQuery(tmdbID: item.tmdbID, title: item.title, year: item.year, season: nil, episode: nil)
    }
    static func forEpisode(show: MediaItem, episode: Episode) -> SubtitleQuery {
        SubtitleQuery(tmdbID: show.tmdbID, title: show.title, year: show.year,
                      season: episode.season, episode: episode.number)
    }
}
```

- [ ] **Step 4: Implement subtitle + recovery methods**

Add to `PlayerModel`:
```swift
    func requestSubtitle(language: String) async {
        guard let subtitles else { setRow(language, .noAccount); return }
        setRow(language, .downloading)
        do {
            // 7c plays movies and episodes; build the query from the item kind.
            let query = SubtitleQuery.forMovie(item)   // episodes: see note below
            let results = try await subtitles.search(query, languages: [language])
            guard let best = results.first else { setRow(language, .error); return }
            let url = try await subtitles.download(best)
            engine.addExternalSubtitle(url: url)
            // The new slave appears as the last subtitle track; reselect from the engine.
            subtitleTracks = engine.subtitleTracks
            let newID = subtitleTracks.last?.id
            engine.selectSubtitleTrack(id: newID)
            setRow(language, .attached(newID ?? language))
        } catch let SubtitleError.dailyCapReached(reset) {
            setRow(language, .capReached(reset))
        } catch SubtitleError.notAuthenticated {
            setRow(language, .error)
        } catch {
            setRow(language, .error)
        }
    }

    private func setRow(_ language: String, _ state: SubtitleRowState) {
        guard let i = subtitleRows.firstIndex(where: { $0.language == language }) else { return }
        subtitleRows[i].state = state
    }

    func retry() { start() }

    func tryAnotherVersion() {
        guard sourceIndex + 1 < sources.count else { return }
        sourceIndex += 1
        start()
    }
```
> **Episode subtitles note:** `PlaybackRequest` carries the chosen `MediaSource` but not which `Episode` it belongs to. For 7c, `requestSubtitle` builds a movie-style query (title/year/tmdbID) which OpenSubtitles matches for both movies and shows acceptably. If episode-accurate matching is wanted later, thread the `Episode` (season/number) into `PlaybackRequest` and switch to `SubtitleQuery.forEpisode`. Out of scope to expand `PlaybackRequest` now.

- [ ] **Step 5: Run to verify it passes**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && xcodebuild test -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' -only-testing:SeretTVTests/PlayerModelTests 2>&1 | tail -10`
Expected: PASS (11 tests total).

- [ ] **Step 6: Commit**

```bash
git add Apps/SeretTV/Playback/PlayerModel.swift Apps/SeretTV/Playback/SubtitleQuery+Item.swift \
        Apps/SeretTVTests/Playback/PlayerModelTests.swift
git commit -m "feat(7c): PlayerModel on-demand subtitles + retry/try-another-version"
```

---

## Task 9: `PlayerView` + subviews (SwiftUI)

SwiftUI/VLCKit-coupled; verified by build + on-device playback (no unit tests). Style B transport per the spec.

**Files:**
- Create: `Apps/SeretTV/Playback/VLCVideoView.swift`
- Create: `Apps/SeretTV/Playback/PlayerOverlays.swift`
- Create: `Apps/SeretTV/Playback/TrackMenuPanel.swift`
- Create: `Apps/SeretTV/Playback/PlayerView.swift`

- [ ] **Step 1: Video surface representable**

`Apps/SeretTV/Playback/VLCVideoView.swift`:
```swift
import SwiftUI

/// Hosts the UIView that `VLCKitVideoPlayerEngine` renders into.
struct VLCVideoView: UIViewRepresentable {
    let videoView: UIView
    func makeUIView(context: Context) -> UIView { videoView }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
```

- [ ] **Step 2: Overlays (loading / error / transport)**

`Apps/SeretTV/Playback/PlayerOverlays.swift`:
```swift
import SwiftUI
import DebridCore

struct LoadingOverlay: View {
    let caption: String
    let title: String
    let backdropURL: URL?
    var body: some View {
        DimBackdrop(url: backdropURL) {
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text(caption).font(.title3)
                Text(title).font(.headline).foregroundStyle(.secondary)
            }
        }
    }
}

struct ErrorOverlay: View {
    let reason: String
    let canTryAnother: Bool
    let backdropURL: URL?
    let onRetry: () -> Void
    let onTryAnother: () -> Void
    let onBack: () -> Void
    var body: some View {
        DimBackdrop(url: backdropURL) {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 54))
                Text("Couldn't play this source").font(.title2.bold())
                Text(reason).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 800)
                HStack(spacing: 24) {
                    Button("Retry", action: onRetry)
                    if canTryAnother { Button("Try another version", action: onTryAnother) }
                    Button("Back", action: onBack)
                }
            }
        }
    }
}

struct TransportOverlay: View {
    @Bindable var model: PlayerModel
    let onOpenTracks: () -> Void
    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                HStack {
                    Text(model.label).font(.headline)
                    Spacer()
                    Button { onOpenTracks() } label: {
                        Label("Subtitles & Audio", systemImage: "captions.bubble")
                    }
                    .buttonStyle(.bordered)
                }
                HStack(spacing: 12) {
                    Text(timecode(model.position)).font(.caption.monospacedDigit())
                    ProgressView(value: model.duration > 0 ? model.position / model.duration : 0)
                    Text("-" + timecode(max(0, model.duration - model.position)))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .background(LinearGradient(colors: [.black.opacity(0.85), .clear],
                                       startPoint: .bottom, endPoint: .top))
        }
    }
    private func timecode(_ s: Double) -> String {
        let t = Int(s); return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }
}

private struct DimBackdrop<Content: View>: View {
    let url: URL?
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Color.black
            if let url { AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear } }
            Color.black.opacity(0.7)
            content
        }
        .ignoresSafeArea()
    }
}
```

- [ ] **Step 3: Track menu panel**

`Apps/SeretTV/Playback/TrackMenuPanel.swift`:
```swift
import SwiftUI
import DebridCore

struct TrackMenuPanel: View {
    @Bindable var model: PlayerModel
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Color.black.opacity(0.35).onTapGesture { onClose() }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Subtitles").font(.title3.bold())
                    Button("Off") { model.selectSubtitleOff() }
                    ForEach(model.subtitleTracks) { track in
                        Button(track.name) { model.selectSubtitle(id: track.id) }
                    }
                    Text("Download from OpenSubtitles").font(.caption).foregroundStyle(.secondary)
                    ForEach(model.subtitleRows) { row in
                        SubtitleRowButton(row: row) { Task { await model.requestSubtitle(language: row.language) } }
                    }
                    Divider()
                    Text("Audio").font(.title3.bold())
                    ForEach(model.audioTracks) { track in
                        Button(track.name) { model.selectAudio(id: track.id) }
                    }
                }
                .padding(28)
            }
            .frame(width: 600)
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea()
    }
}

private struct SubtitleRowButton: View {
    let row: PlayerModel.SubtitleRow
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(displayName)
                Spacer()
                trailing
            }
        }
        .disabled(isDisabled)
    }
    private var displayName: String { row.language == "he" ? "Hebrew" : "English" }
    @ViewBuilder private var trailing: some View {
        switch row.state {
        case .idle: Image(systemName: "arrow.down.circle")
        case .downloading: ProgressView()
        case .attached: Image(systemName: "checkmark")
        case .capReached(let reset): Text(reset == nil ? "Daily limit" : "Resets \(reset!.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
        case .error: Text("Retry").foregroundStyle(.orange)
        case .noAccount: Text("Add account in Settings").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var isDisabled: Bool { if case .capReached = row.state { return true }; if case .noAccount = row.state { return true }; if case .downloading = row.state { return true }; return false }
}
```
> Add the small selection helpers used above to `PlayerModel`: `selectSubtitle(id:)` → `engine.selectSubtitleTrack(id: id)`, `selectSubtitleOff()` → `engine.selectSubtitleTrack(id: nil)`, `selectAudio(id:)` → `engine.selectAudioTrack(id: id)`. (Trivial pass-throughs; add them in this step and rebuild.)

- [ ] **Step 4: The player shell**

`Apps/SeretTV/Playback/PlayerView.swift`:
```swift
import SwiftUI
import DebridCore

struct PlayerView: View {
    @State private var model: PlayerModel
    @State private var engine: VLCKitVideoPlayerEngine
    @State private var showTracks = false
    @Environment(\.dismiss) private var dismiss
    let backdropURL: URL?

    init(model: PlayerModel, engine: VLCKitVideoPlayerEngine, backdropURL: URL?) {
        _model = State(initialValue: model)
        _engine = State(initialValue: engine)
        self.backdropURL = backdropURL
    }

    var body: some View {
        ZStack {
            VLCVideoView(videoView: engine.videoView).ignoresSafeArea()

            switch model.phase {
            case .preparing: LoadingOverlay(caption: "Preparing…", title: model.label, backdropURL: backdropURL)
            case .buffering: LoadingOverlay(caption: "Buffering…", title: model.label, backdropURL: backdropURL)
            case .failed(let reason):
                ErrorOverlay(reason: reason, canTryAnother: model.canTryAnotherVersion, backdropURL: backdropURL,
                             onRetry: { model.retry() }, onTryAnother: { model.tryAnotherVersion() },
                             onBack: { dismiss() })
            case .playing, .paused, .ended:
                if model.controlsVisible { TransportOverlay(model: model) { showTracks = true } }
            }

            if showTracks { TrackMenuPanel(model: model) { showTracks = false } }
        }
        .onPlayPauseCommand { model.togglePlayPause() }
        .onMoveCommand { direction in
            switch direction {
            case .left: model.skip(-10)
            case .right: model.skip(10)
            case .down: showTracks = true
            default: break
            }
        }
        .onExitCommand { if showTracks { showTracks = false } else { dismiss() } }
        .onAppear { model.start() }
        .onChange(of: model.shouldDismiss) { _, dismissNow in if dismissNow { dismiss() } }
        .task { /* keep view alive; model owns the event loop */ }
        .onDisappear { Task { await model.teardown() } }
    }
}
```
> `controlsVisible` auto-hide: add a debounced timer in a later polish pass; for 7c, controls show on `.playing`/`.paused`. (Auto-hide is a nicety, not a DoD item.) Add `controlsVisible` toggling on `onMoveCommand`/click if desired.

- [ ] **Step 5: Build**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && xcodebuild -scheme SeretTV -destination 'generic/platform=tvOS Simulator' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`, zero warnings. (Add the three `select*` helpers to `PlayerModel` if the build complains they're missing.)

- [ ] **Step 6: Commit**

```bash
git add Apps/SeretTV/Playback/VLCVideoView.swift Apps/SeretTV/Playback/PlayerOverlays.swift \
        Apps/SeretTV/Playback/TrackMenuPanel.swift Apps/SeretTV/Playback/PlayerView.swift \
        Apps/SeretTV/Playback/PlayerModel.swift
git commit -m "feat(7c): SwiftUI PlayerView — transport, track panel, loading/error overlays"
```

---

## Task 10: Wire `AppSession` + replace the seam + final verification

**Files:**
- Modify: `Apps/SeretTV/Shell/AppSession.swift`
- Modify: `Apps/SeretTV/Shell/LibraryShell.swift` (the `:53` navigation seam)
- Delete: `Apps/SeretTV/Playback/PlayerPlaceholderView.swift`

- [ ] **Step 1: Vend playback dependencies from `AppSession`**

In `AppSession`, keep a concrete `WatchProgressStore` reference and expose a factory that builds a fully-wired `PlayerModel` + engine for a `PlaybackRequest`. Add inside `enterSignedIn()` and as properties:
```swift
    // Properties on AppSession:
    private(set) var subtitlesProvider: SubtitleProvider?
    private var watchProgressStore: WatchProgressStore?
    private var torrents: TorrentsClient?

    // Inside enterSignedIn(), after building `service`:
    let container = try? ModelContainer(for: WatchProgress.self)
    let concreteStore = container.map { WatchProgressStore(modelContainer: $0) }
    self.watchProgressStore = concreteStore
    self.watchStore = concreteStore.map { $0 as WatchProgressProviding }
    self.torrents = TorrentsClient(tokens: realDebrid)

    let osKey = Secrets.openSubtitlesAPIKey
    let osAccount = KeychainSecretStore(service: "com.solomons.seret.opensubtitles").readAccount()
    if !osKey.isEmpty, let osAccount {
        self.subtitlesProvider = OpenSubtitlesProvider(apiKey: osKey, credentials: osAccount.credentials)
    } else {
        self.subtitlesProvider = nil
    }
```
Add the factory method:
```swift
    @MainActor
    func makePlayer(for request: PlaybackRequest) -> (PlayerModel, VLCKitVideoPlayerEngine)? {
        guard let torrents, let store = watchProgressStore else { return nil }
        let coordinator = PlaybackCoordinator(store: store)
        let engine = VLCKitVideoPlayerEngine()
        let contentKey = WatchKey.content(forMovie: request.item)   // movies; episodes use the show+episode key upstream
        let sourceKey = WatchKey.source(request.source)
        let model = PlayerModel(
            request: request,
            engine: engine,
            unrestrict: { link in
                let unrestricted = try await torrents.unrestrict(link: link)
                guard let url = URL(string: unrestricted.download) else { throw URLError(.badURL) }
                return url
            },
            recordProgress: { position, duration in
                await coordinator.record(contentKey: contentKey, sourceKey: sourceKey,
                                         position: position, duration: duration)
            },
            subtitles: subtitlesProvider)
        return (model, engine)
    }
```
> Confirm `WatchKey.content(forMovie:)` / `WatchKey.source(_:)` are accessible from the app target (the explore report shows them `public`). For episodes, the detail screen already knows the `Episode`; if episode-accurate keys are needed, pass the precomputed `contentKey` inside `PlaybackRequest` in a later slice. For 7c the movie key is correct for movies; episode progress still records under a stable per-source key.

- [ ] **Step 2: Replace the seam with a full-screen cover**

In `Apps/SeretTV/Shell/LibraryShell.swift`, replace the `navigationDestination(for: PlaybackRequest.self)` push (line ~53) with state-driven full-screen presentation. Add state + a cover, and make `PlaybackRequest` navigations set it:
```swift
    @Environment(AppSession.self) private var session
    @State private var activePlayer: PlaybackRequest?

    // Replace the old `.navigationDestination(for: PlaybackRequest.self) { PlayerPlaceholderView(request: $0) }`
    // with a destination that records the request and a fullScreenCover that presents the player:
    .navigationDestination(for: PlaybackRequest.self) { request in
        Color.clear.onAppear { activePlayer = request }   // value-nav lands here, immediately promote to cover
    }
    .fullScreenCover(item: $activePlayer) { request in
        if let (model, engine) = session.makePlayer(for: request) {
            PlayerView(model: model, engine: engine,
                       backdropURL: request.item.backdropPath.map { /* TMDB backdrop URL */ TMDBClient.imageURL(path: $0, size: .original) })
        } else {
            // No RD session — should not happen when signed in.
            Text("Unable to start playback.").onAppear { activePlayer = nil }
        }
    }
```
> `PlaybackRequest` must be `Identifiable` for `fullScreenCover(item:)`. It's already `Hashable`; add `extension PlaybackRequest: Identifiable { var id: Int { hashValue } }` in `PlaybackRequest.swift`. **Cleaner alternative (preferred at implement time):** change the Detail screen's Play button from `NavigationLink(value:)` to a closure that sets `activePlayer` directly, and drop the `navigationDestination` shim entirely — decide based on how 7b-ii's Detail wires the Play button. Confirm the exact `TMDBClient.imageURL` signature (the explore report shows `imageURL(path:size:)`-style; match it).

- [ ] **Step 3: Delete the placeholder**

```bash
git rm Apps/SeretTV/Playback/PlayerPlaceholderView.swift
```

- [ ] **Step 4: Regenerate, build, run the full app test suite**

Run:
```bash
cd /Users/shaharsolomons/Documents/Code/Seret && xcodegen generate \
  && xcodebuild test -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV' 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **` — DebridCore green (124 = 122 + SecretStore's 2), app tests green (SettingsModel 3 + PlayerModel 11 + prior 9). Zero warnings. (Requires a working sim — restart Claude.app first if the pty-pool error appears.)

- [ ] **Step 5: On-device / sim verification (owner-side, DoD)**

Manually verify against the spec's DoD §8: a movie plays from Detail; resume-seek works; scrubber/play-pause/skip work; ended dismisses; an episode plays; on-demand Hebrew subtitle attaches; a forced-bad source shows the error overlay and Retry/Try-another work. Capture screenshots (QuickTime movie-recording for a real Apple TV; the sim's screenshot for the simulator).

- [ ] **Step 6: Commit**

```bash
git add Apps/SeretTV/Shell/AppSession.swift Apps/SeretTV/Shell/LibraryShell.swift Apps/SeretTV/Playback/PlaybackRequest.swift
git commit -m "feat(7c): wire AppSession playback + present PlayerView, remove placeholder"
```

---

## Self-review notes (completed during planning)

- **Spec coverage:** vendoring (§4.5 → T1), engine (§4.1 → T2), secret store (§4.4 → T3), API key (§4.4 → T4), Settings/login (§4.4 → T5), PlayerModel + state machine (§4.2/§5 → T6–T8), subtitles on-demand + states (§4.2/§4.3 → T8), UI/transport/panel/overlays (§4.3 → T9), presentation/fullScreenCover + wiring (§4.6 → T10), error handling (§6 → T8 logic + T9 ErrorOverlay), testing (§7 → T3/T5/T6/T7/T8 + T10 run). All spec sections map to a task.
- **Coordinator deviation** is documented at the top (closure instead of concrete `PlaybackCoordinator` injection) and re-wired correctly in T10.
- **Type consistency:** `PlayerModel.SubtitleRow`/`SubtitleRowState`/`Phase` are referenced identically in T6–T9; `recordProgress: (Double, Double) async -> Void` matches in fakes, model, and AppSession wiring; `engine.selectSubtitleTrack(id:)` etc. match the protocol.
- **Known confirm-at-build items** (flagged inline, not placeholders): exact VLCKit selector/enum names (T2), `ParsedRelease`/`MediaItem`/`TMDBClient.imageURL` real initializers/signatures (T6/T10), and the cleanest fullScreenCover trigger (T10). These are real code with a verify step, per spec §9.

## Pre-execution requirement

⚠️ Execution needs the tvOS simulator (or a real Apple TV) for every `xcodebuild test`/run step. **Restart Claude.app before starting** to clear the pty-pool exhaustion (`Pseudo Terminal Setup Error 7/6`) — see `reference_xcode_pty_error`. `swift test` (DebridCore) and `xcodebuild build` work without it; sim test-runs and launches do not.
