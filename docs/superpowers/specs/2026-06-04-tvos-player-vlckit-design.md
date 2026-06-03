# Plan 7c — Real VLCKit Player (tvOS) — Design Spec

**Date:** 2026-06-04
**Status:** Approved (brainstorm complete) — ready for `writing-plans`
**Milestone:** Seret — Apple TV app, first UI (Plan 7), slice **7c** (player)
**Predecessors:** 7a (scaffold + sign-in), 7b-i (library grids), 7b-ii (detail + episodes — built the `PlaybackRequest` → `PlayerPlaceholderView` seam this replaces)

---

## 1. Goal

Replace the stub `PlayerPlaceholderView` with a real, VLCKit-backed video player that consumes the existing `PlaybackRequest` seam and plays a Real-Debrid stream end-to-end on Apple TV: **unrestrict → load → resume-seek → play → save progress**, with a custom SwiftUI transport (VLCKit ships no tvOS player chrome), audio/subtitle track selection, on-demand Hebrew/English OpenSubtitles, and buffering/error states.

This is the slice that makes Seret actually *play video*. After it, the brain (Plans 1–6) and the browse/detail UI (7a/7b) are joined by playback.

## 2. Scope

**In scope**
- Vendor + embed `TVVLCKit.xcframework` (XcodeGen, mirroring Nikud's `llama.xcframework`).
- `VLCKitVideoPlayerEngine` — app-side concrete conformer to DebridCore's `VideoPlayerEngine`.
- `PlayerModel` — `@MainActor @Observable` orchestrator + playback state machine + progress-save cadence + on-demand subtitle fetch.
- `PlayerView` (+ subviews) — pure SwiftUI; minimal Apple-style transport, right-side Subtitles & Audio panel, loading/buffering + error overlays; Siri-remote handling. Presented as a `.fullScreenCover`.
- OpenSubtitles credentials: `Secrets.openSubtitlesAPIKey` (build-time) + a Settings login form (username/password) saved via a new generic `KeychainSecretStore`.
- `AppSession` wiring for the playback + subtitle dependencies.

**Out of scope (later plans)**
- Home / Continue Watching feed.
- "Up Next" / play-next-episode at end of an episode.
- Configurable subtitle languages (hardcoded He + En in 7c).
- Search / add-to-library flow.
- iPhone / iPad app (Plan 8, `MobileVLCKit`).

## 3. Foundations reused (DebridCore brain — no changes to existing code)

7c changes **no existing DebridCore code** — the brain (Plans 1–6) is composed as-is. The only possible *new* DebridCore file is the generic `KeychainSecretStore` infra (§4.4), which is storage plumbing, not domain logic. The seams it composes (signatures verified against the repo):

**Playback engine seam** — `Packages/DebridCore/.../Playback/VideoPlayerEngine.swift`
```swift
@MainActor
public protocol VideoPlayerEngine: AnyObject {
    func load(url: URL, headers: [String: String])
    func play()
    func pause()
    func seek(to seconds: Double)
    var audioTracks: [MediaTrack] { get }
    var subtitleTracks: [MediaTrack] { get }
    func selectAudioTrack(id: String?)
    func selectSubtitleTrack(id: String?)   // nil = off
    func addExternalSubtitle(url: URL)
    var events: AsyncStream<PlaybackEvent> { get }
}
```
Model types (`Playback/PlaybackModel.swift`):
- `PlaybackEvent`: `.state(PlaybackState)` | `.time(PlaybackTime)`
- `PlaybackState`: `idle, buffering, playing, paused, ended, failed(String)`
- `PlaybackTime`: `position: Double`, `duration: Double`
- `MediaTrack`: `id: String`, `kind: TrackKind`, `name: String`, `language: String?`
- `TrackKind`: `audio, subtitle`

**Resume + progress** — `Playback/PlaybackCoordinator.swift`
```swift
public struct PlaybackCoordinator: Sendable {
    public init(store: WatchProgressStore, finishedThreshold: Double = 0.95)
    public func resumePosition(contentKey: String) async -> Double
    public func record(contentKey: String, sourceKey: String,
                       position: Double, duration: Double) async   // marks finished when position/duration >= 0.95
}
```
Note: takes the **concrete** `WatchProgressStore` actor (not the erased `WatchProgressProviding`).

**Unrestrict** — `RealDebrid/TorrentsClient.swift` + `RealDebridResourceModels.swift`
```swift
public func unrestrict(link: String) async throws -> UnrestrictedLink
public struct UnrestrictedLink { public let download: String; public let filename: String; public let filesize: Int; public let mimeType: String? }
```
The streamable URL is `UnrestrictedLink.download`. Input is `MediaSource.restrictedLink`.

**Subtitles** — `Subtitles/SubtitleProvider.swift` + `OpenSubtitlesProvider.swift`
```swift
public protocol SubtitleProvider: Sendable {
    func search(_ query: SubtitleQuery, languages: [String]) async throws -> [SubtitleResult]
    func download(_ result: SubtitleResult) async throws -> URL
}
public struct SubtitleQuery { public var tmdbID: Int?; public var title: String; public var year: Int?; public var season: Int?; public var episode: Int? }
public struct SubtitleResult { public let fileID: Int; public let language: String; public let release: String?; public let fileName: String?; public let downloadCount: Int? }
public enum SubtitleError: Error { case dailyCapReached(resetTime: Date?); case notAuthenticated; case invalidResponse }

public actor OpenSubtitlesProvider: SubtitleProvider {
    public struct Credentials: Sendable { public let username: String; public let password: String }
    public init(apiKey: String, credentials: Credentials, http: HTTPClient = .init(), userAgent: String = "Seret v1")
}
```
`search` uses the API key only; `download` triggers a lazy login (username/password → JWT, cached). HTTP 403/406 → `.dailyCapReached`.

**The seam being replaced** — `Apps/SeretTV/Playback/`
```swift
struct PlaybackRequest: Hashable { let item: MediaItem; let source: MediaSource; let resumeAt: Double?; let label: String }
```
Presented at `Apps/SeretTV/Shell/LibraryShell.swift:53`:
```swift
.navigationDestination(for: PlaybackRequest.self) { request in PlayerPlaceholderView(request: request) }
```

**Watch progress** — `Persistence/WatchProgressStore.swift`
```swift
@ModelActor public actor WatchProgressStore {
    public func progress(forContentKey:) throws -> WatchState?
    public func record(contentKey:sourceKey:positionSeconds:durationSeconds:finished:at:) throws
    public func recentlyWatched(limit:) throws -> [WatchState]
}
```
Keys via `WatchKey`: movie → `item.id`; episode → `"\(show.id):\(episode.id)"`; source → `"\(torrentID)#\(fileID ?? "-")"`.

## 4. Architecture

New code is **app-side** (`Apps/SeretTV`), because TVVLCKit ships with the app and DebridCore must stay VLC-free.

### 4.1 `VLCKitVideoPlayerEngine` (app target)
Concrete conformer to `VideoPlayerEngine`, wrapping `VLCMediaPlayer` from TVVLCKit. `@MainActor`, `final class`.
- **load(url:headers:):** set `player.media = VLCMedia(url:)`; apply any `headers` as VLCMedia options if non-empty (none needed for RD CDN links — pass `[:]`). Set `player.drawable` to the hosted video `UIView`.
- **play/pause/seek:** delegate to `VLCMediaPlayer.play()/pause()`; `seek` sets `player.time = VLCTime(int: ms)` (or `player.position` ratio).
- **events:** an `AsyncStream<PlaybackEvent>`; a `VLCMediaPlayerDelegate` translates `mediaPlayerStateChanged` → `.state(...)` (map VLCKit's `VLCMediaPlayerState` to our `PlaybackState`, incl. `.error → .failed(reason)`) and `mediaPlayerTimeChanged` → `.time(PlaybackTime(position:duration:))` (duration from `player.media.length`).
- **tracks:** map VLCKit's integer track indexes/names (`audioTrackIndexes`/`audioTrackNames`, `videoSubTitlesIndexes`/`videoSubTitlesNames`) ↔ our `MediaTrack` (String `id` = the index as string). `selectAudio/SubtitleTrack(id:)` sets the current index (`-1`/nil = off for subtitles).
- **addExternalSubtitle(url:):** `player.addPlaybackSlave(url, type: .subtitle, enforce: true)` (3.6.0 API; confirm exact selector at implement time — older builds use `openVideoSubTitlesFromFile`). The new slave then appears as a selectable subtitle track.

> **Open item:** exact VLCKit selector names vary by version. Confirm `addPlaybackSlave`, the track-enumeration accessors, and the state enum cases against the vendored 3.6.0 headers during implementation. This class is the only VLCKit-coupled unit; keep it thin.

### 4.2 `PlayerModel` (`@MainActor @Observable`)
The orchestrator and single source of UI truth. Constructed per playback session with injected dependencies (all protocol/closure-typed so it's testable without VLCKit or the network):
- `request: PlaybackRequest`
- `engine: VideoPlayerEngine`
- `unrestrict: (String) async throws -> URL` (wraps `TorrentsClient.unrestrict` → `.download`)
- `coordinator: PlaybackCoordinator`
- `subtitles: SubtitleProvider?` (nil when no OpenSubtitles login saved)
- precomputed `contentKey` / `sourceKey` (from `WatchKey`)

Published state (drives `PlayerView`):
- `phase: Phase` — `.preparing | .buffering | .playing | .paused | .ended | .failed(String)`
- `position`, `duration`, `controlsVisible`
- `audioTracks`, `subtitleTracks`, selected ids
- `subtitleRows: [SubtitleRow]` — per-language on-demand state (`.idle | .downloading | .attached(trackID) | .capReached(Date?) | .error | .noAccount`)

Lifecycle:
1. `start()` → `phase = .preparing`; `let url = try await unrestrict(request.source.restrictedLink)`; `engine.load(url:headers:[:])`; if `request.resumeAt ?? 0 > 0` → `engine.seek(to:)`; `engine.play()`; begin consuming `engine.events`.
2. Event loop: `.state` → map to `phase` + refresh track lists on first `.playing`; `.time` → update `position/duration` + **throttled** save.
3. `togglePlayPause()`, `skip(±10)`, `scrub(to:)`.
4. **Save cadence:** call `coordinator.record(...)` at most ~once per **5s** of playback, plus immediately on pause, on `.ended`, and on teardown/dismiss.
5. `.ended` → final `record(...)` (≥95% ⇒ finished) → signal `PlayerView` to dismiss.
6. **Subtitles (on-demand):** `requestSubtitle(language:)` → row `.downloading` → build `SubtitleQuery` from `request.item` (+ season/episode if a show) → `subtitles.search(_, languages:[lang])` → `download(best)` → `engine.addExternalSubtitle(url:)` → select it → row `.attached`. Map `SubtitleError.dailyCapReached → .capReached`, `.notAuthenticated`/other → `.error`. If `subtitles == nil` → rows are `.noAccount`.
7. **retry()** (re-run `start()` on the same source) and **tryAnotherVersion()** (advance to the next `MediaSource` via `item.sources.bestFirst()` ordering, then `start()`), surfaced from the error overlay. "Try another version" shown only when `item.sources.count > 1`.

### 4.3 `PlayerView` + subviews (SwiftUI)
- Presented via **`.fullScreenCover`** (change the `LibraryShell:53` seam from `navigationDestination` push to a binding-driven cover, or push a full-screen route — see §4.6). Immersive, no sidebar.
- `VLCVideoView: UIViewRepresentable` — vends the `UIView` the engine renders into; wraps **only** the video surface.
- **Transport overlay (style B, minimal):** title + "Subtitles & Audio" affordance on the top row; slim scrubber with elapsed / −remaining below. No on-screen button cluster. Auto-hide after ~4s; any input reveals.
- **Remote mapping:** `onPlayPauseCommand` → toggle; `onMoveCommand(.left/.right)` → skip ∓10s; `onExitCommand` → hide controls, then dismiss; swipe-down / a focusable button → open the Subtitles & Audio panel; click → show/activate.
  - **Known risk:** continuous proportional swipe-to-scrub on the touch surface may not be reachable in pure SwiftUI; discrete skip via `onMoveCommand` comes free. If proportional scrub is wanted, add a small `UIViewRepresentable` hosting a `UIPanGestureRecognizer`. Treated as an enhancement, not a blocker.
- **Subtitles & Audio panel:** right-side overlay over a dimmed (still-playing) video. Subtitles section: `Off`, embedded tracks, then "Download from OpenSubtitles" with Hebrew/English rows reflecting `SubtitleRow` state (idle → downloading → attached ✓ → cap-reached(disabled, reset time) → error(Retry) → noAccount("Add OpenSubtitles account in Settings")). Audio section: list `audioTracks` with the selected one checked.
- **Loading / buffering overlay:** spinner + title over a dimmed `backdropPath`; caption "Preparing…" (`.preparing`) or "Buffering…" (`.buffering`).
- **Error overlay:** ⚠️ + "Couldn't play this source" + reason from `.failed(String)`; actions **Retry**, **Try another version** (only if >1 source), **Back**.

### 4.4 OpenSubtitles credentials
- **API key (build-time):** add `OPENSUBTITLES_API_KEY` to `Secrets.xcconfig` (gitignored) + `Secrets.example.xcconfig` (template); add `<key>OpenSubtitlesAPIKey</key><string>$(OPENSUBTITLES_API_KEY)</string>` to `Apps/SeretTV/Info.plist`; add `Secrets.openSubtitlesAPIKey` accessor mirroring `tmdbAPIKey`.
- **Login (per-user, runtime):** new generic `KeychainSecretStore` (DebridCore) keyed by `service`/`account`, storing a `Codable` payload (`{username, password}`). RD's `KeychainTokenStore` is left untouched (could migrate onto the generic store later). *(This is the one small DebridCore-adjacent addition; it is generic infra, not RD/TMDB logic — it does not violate the "no brain logic in app" rule and may live in DebridCore alongside the keychain code, or app-side. Decide at plan time; default: DebridCore, next to `KeychainTokenStore`.)*
- **Settings form:** extend `Apps/SeretTV/Shell/SettingsView.swift` with an "OpenSubtitles account" section — username + password fields, Save / Remove, status line. Saving creates `OpenSubtitlesProvider.Credentials` in the keychain.

### 4.5 TVVLCKit vendoring
- Finalize `Scripts/fetch-frameworks.sh`: set `PINNED_URL` + `EXPECTED_SHA256` for **TVVLCKit 3.6.0**, verify the extracted directory name, and uncomment the `mv … Frameworks/TVVLCKit.xcframework` + drop the guard. `Frameworks/` stays gitignored.
- `project.yml` → `SeretTV.dependencies`: add
  ```yaml
  - framework: Frameworks/TVVLCKit.xcframework
    embed: true
    codeSign: true
  ```
  (`SeretTV` already sets `LD_RUNPATH_SEARCH_PATHS: [$(inherited), @executable_path/Frameworks]`, which is correct for a tvOS app bundle — no change needed.)
- Document the prerequisite (`Scripts/fetch-frameworks.sh` must run before opening the project) in README / CLAUDE.md.

> **External input to resolve at plan/execute time:** the exact `https://download.videolan.org/...` TVVLCKit 3.6.0 xcframework tarball URL + its sha256. Verify the artifact exists and downloads before wiring the build.

### 4.6 `AppSession` wiring
In `enterSignedIn()` (`Apps/SeretTV/Shell/AppSession.swift`):
- Build a `PlaybackCoordinator` from the **concrete** `WatchProgressStore` (currently erased to `WatchProgressProviding` — keep a concrete reference for the coordinator).
- Build `OpenSubtitlesProvider(apiKey: Secrets.openSubtitlesAPIKey, credentials:)` **only if** a login is saved in the keychain; otherwise leave the subtitle provider `nil`.
- Vend an engine factory (`() -> VideoPlayerEngine` returning a fresh `VLCKitVideoPlayerEngine`) and the above deps so `PlayerView`/`PlayerModel` can be constructed when a `PlaybackRequest` is presented.

## 5. State machine (`PlayerModel.Phase`)

| From | Event | To |
|------|-------|----|
| (init) | `start()` | `.preparing` |
| `.preparing` | unrestrict + load ok, engine `.buffering` | `.buffering` |
| `.preparing` | unrestrict throws | `.failed(reason)` |
| `.buffering` | engine `.playing` | `.playing` |
| `.playing` | engine `.buffering` | `.buffering` |
| `.playing` | user pause / engine `.paused` | `.paused` |
| `.paused` | user play | `.playing` |
| any | engine `.failed(s)` | `.failed(s)` |
| `.playing`/`.buffering` | engine `.ended` | `.ended` (save + dismiss) |
| `.failed` | retry() | `.preparing` |
| `.failed` | tryAnotherVersion() | `.preparing` (next source) |

## 6. Error handling
- **Unrestrict failure / no playable URL:** `.failed("The Real-Debrid link could not be opened.")` + Retry / Try another version / Back.
- **Engine load/play failure:** `.failed(reason)` from VLCKit (e.g. unsupported / network) — same overlay.
- **Subtitle errors:** surfaced inline in the panel rows only (never block playback): `.capReached(reset)`, `.error` (with Retry), `.noAccount`.
- **No crashes / no silent dead-ends:** every failure path lands on a visible state with an action.

## 7. Testing
- **`PlayerModel` unit tests (app-hosted, fakes):** a `FakeVideoPlayerEngine` exposing a controllable `AsyncStream` continuation + recorded calls; a fake `unrestrict` closure; a `FakeSubtitleProvider`. Assert: preparing→buffering→playing on success; resume-seek called with `request.resumeAt`; save throttle (~5s + pause + ended + teardown); `.ended` marks finished + dismiss; unrestrict-throw → `.failed` → retry re-runs; tryAnotherVersion advances source; subtitle happy path attaches + selects; `dailyCapReached`/`notAuthenticated` → correct row state; `nil` provider → `.noAccount` rows.
- **`VLCKitVideoPlayerEngine`:** thin; verified by real playback on device/sim, not unit tests (needs real VLCKit).
- **Build:** zero warnings; `swift test` (DebridCore, unchanged) stays green; app builds.
- **No SwiftData suites added** in 7c, so the shared `@Suite(.serialized) SwiftDataSuite` parent hazard does not newly apply — but if any test touches `WatchProgressStore`, nest it under that parent.

## 8. Definition of Done
1. `Scripts/fetch-frameworks.sh` fetches + verifies TVVLCKit 3.6.0 into `Frameworks/`; `project.yml` embeds it; app builds zero-warning.
2. `PlayerView` replaces `PlayerPlaceholderView` at the seam; presented full-screen.
3. On device/sim: a **movie** plays from a `PlaybackRequest`; resume-seek works from a prior position; scrubber + play/pause + skip work; **ended** marks finished and dismisses.
4. An **episode** plays from the show detail.
5. Subtitles & Audio panel lists tracks; an **on-demand Hebrew download** attaches and displays; daily-cap and no-account states render.
6. A forced failure (bad source) shows the error overlay; **Retry** and **Try another version** work.
7. `PlayerModel` unit tests green.

> **Verification reality:** 7c is a video player — unverifiable without launching the tvOS sim or a real Apple TV. The dev/agent environment hits the **Claude.app pty-pool "Pseudo Terminal Setup Error 7/6"** on sim launch; **restart Claude.app before building/verifying** (see `reference_xcode_pty_error`). `swift test` + `xcodebuild build` work without a restart. App-target tests (⌘U) + on-device playback screenshots are owner-side.

## 9. Open items (resolve during planning/execution)
1. **TVVLCKit 3.6.0 artifact** — exact tarball URL + sha256 (verify it downloads).
2. **VLCKit selector names** — confirm `addPlaybackSlave`, track-enumeration accessors, and state-enum mapping against the vendored 3.6.0 headers.
3. **Proportional swipe-to-scrub** — ship discrete skip first; add a UIKit pan shim only if wanted.
4. **`KeychainSecretStore` location** — DebridCore (next to `KeychainTokenStore`, default) vs app target.
5. **Full-screen presentation mechanics** — `.fullScreenCover` bound from `LibraryShell` vs a full-screen nav route; pick the cleanest that hides the sidebar.
6. **`SubtitleQuery` construction** — small app-side helpers to build a query from `MediaItem` / `(show, episode)` (no such factory exists on the struct today).
