# Seret — VideoPlayerEngine + PlaybackCoordinator — Design

**Status:** Draft for review
**Date:** 2026-06-03
**Owner:** Shahar Solomons
**Context:** Slice 3 of 3 of **Plan 6** ("finish the brain"): persistence ✓ → subtitles ✓ → **`VideoPlayerEngine`**. Realizes [`2026-06-02-seret-design.md`](2026-06-02-seret-design.md) §5.6. Built test-first in `DebridCore`; **no UI / no VLCKit** in the package.

---

## 1. Goal

Define the **playback seam** — a `VideoPlayerEngine` protocol + playback model that each app implements with VLCKit — and a `PlaybackCoordinator` that bridges playback to `WatchProgressStore` (resume on load, save progress, mark finished). After this the brain is **feature-complete**; Plan 7 builds the Apple TV app on top.

## 2. Scope

**In:** the `VideoPlayerEngine` protocol; the playback value-type model (`PlaybackState`, `PlaybackTime`, `MediaTrack`, `TrackKind`, `PlaybackEvent`); the `PlaybackCoordinator` (resume/save bridge to `WatchProgressStore`).

**Out (deliberately):**
- The concrete **VLCKit** engine + the SwiftUI player view — Plan 7 (per-platform; VLCKit is UIKit-bound).
- The **AVPlayer fast-path** for hardware-decodable files — Stage 3 (the seam allows it later).
- **Save throttling** — app-driven (the app calls `record` on a timer / pause / background).
- Embedded-track *enumeration implementation* — the concrete engine's job (the protocol just exposes the lists).

## 3. Decisions (from brainstorming)

1. **Includes the `PlaybackCoordinator`** (shared, testable resume/save logic), not protocol-only — otherwise the slice is near-pure declarations and the resume/save logic gets duplicated per app.
2. **The protocol is intentionally minimal.** It's the one seam designed before its real implementer; Plan 7 validates the callback shape against VLCKit's actual delegate API and refines if needed. No point over-specifying what we can't yet exercise.
3. **The coordinator is app-driven and stateless** — the app wires the engine's events to `coordinator.record(...)` (throttling lives in the app). This keeps the coordinator decoupled from the engine's callback mechanism and trivially testable.

## 4. Components (`DebridCore/Playback/`)

### 4.1 Playback model (`Sendable` value types) — `Playback/PlaybackModel.swift`
- `enum PlaybackState: Sendable, Equatable` — `.idle`, `.buffering`, `.playing`, `.paused`, `.ended`, `.failed(String)`.
- `struct PlaybackTime: Sendable, Equatable` — `position: Double`, `duration: Double` (seconds).
- `enum TrackKind: Sendable, Equatable` — `.audio`, `.subtitle`.
- `struct MediaTrack: Sendable, Equatable, Identifiable` — `id: String`, `kind: TrackKind`, `name: String`, `language: String?`.
- `enum PlaybackEvent: Sendable, Equatable` — `.state(PlaybackState)`, `.time(PlaybackTime)`.

### 4.2 `VideoPlayerEngine` — `Playback/VideoPlayerEngine.swift`
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
    func addExternalSubtitle(url: URL)       // consumes slice 2's downloaded temp-file URL

    var events: AsyncStream<PlaybackEvent> { get }   // time + state updates
}
```
`@MainActor` + `AnyObject` because the concrete engine (VLCKit) is a UIKit-bound reference type. The protocol + model live in `DebridCore` (no VLCKit import); the engine is implemented per app target.

### 4.3 `PlaybackCoordinator` — `Playback/PlaybackCoordinator.swift`
A `Sendable`, stateless bridge between playback and `WatchProgressStore`:
```swift
public struct PlaybackCoordinator: Sendable {
    public init(store: WatchProgressStore, finishedThreshold: Double = 0.95)

    /// The position to resume from for a title — 0 if there's no progress or it's already finished.
    public func resumePosition(contentKey: String) async -> Double

    /// Persist the current position (best-effort — swallows store errors so playback is never
    /// interrupted), marking the title finished once `position/duration >= finishedThreshold`.
    public func record(contentKey: String, sourceKey: String, position: Double, duration: Double) async
}
```
- `resumePosition` reads `WatchProgressStore.progress(forContentKey:)`; returns `positionSeconds` unless the row is absent or `finished` (→ `0`). Any read failure → `0` (graceful).
- `record` computes `finished = duration > 0 && position / duration >= finishedThreshold`, then `try? await store.record(...)` (best-effort).

The `contentKey`/`sourceKey` are derived by the app from the `MediaItem`/`Episode` + chosen `MediaSource` via the existing `WatchKey` helpers; the coordinator takes them as strings (it stays decoupled from the library model).

## 5. Key flow (app, Plan 7)

Play: derive `contentKey`/`sourceKey` (`WatchKey`) → `engine.load(url: unrestrictedURL, headers:)` → `engine.seek(to: await coordinator.resumePosition(contentKey:))` → `engine.play()`. The app consumes `engine.events`: on `.time`, it calls `coordinator.record(...)` (throttled, e.g. every ~5 s + on pause/background); on `.state(.ended)` it records a final (finished) position. Subtitles: download via slice 2 → `engine.addExternalSubtitle(url:)`.

## 6. Error handling

- Engine failures surface as `PlaybackState.failed(message)` through `events`.
- `coordinator.record` swallows store errors (best-effort; never interrupts playback — per §8 of the main spec).
- `coordinator.resumePosition` returns `0` on any read failure, missing progress, or finished title.

## 7. Testing (test-first; Swift Testing)

- **`PlaybackCoordinator`** is the real test target, over a fresh **in-memory `WatchProgressStore`** — so the suite **MUST be `@Suite(.serialized)`** (SwiftData parallel-runner SIGSEGV gotcha; see CLAUDE.md):
  - `resumePosition` returns the saved position; `0` when the row is `finished`; `0` when there's no row.
  - `record` persists `position`/`duration`; computes `finished` at the threshold (`≥ 0.95` → true, below → false); a second `record` upserts (no duplicate row).
- **`VideoPlayerEngine`**: a tiny `@MainActor` **mock** conformer (records calls) + a test driving `load`/`play`/`seek`/`selectSubtitleTrack`/`addExternalSubtitle` to prove the protocol is implementable and ergonomic (the protocol has no `DebridCore` consumer — the coordinator is independent — so a mock is what exercises it).
- Model types are plain value types; assert `Equatable` where it's load-bearing (the mock/coordinator tests already exercise them).

## 8. Dependencies

None new. `DebridCore` uses `@MainActor` + `AsyncStream` (Swift concurrency — not UI). VLCKit + the SwiftUI player view are app-target only (Plan 7).

## 9. Open questions for the plan

- The `events` `AsyncStream` shape (single-consumer; one stream per engine) — Plan 7 validates against VLCKit; this slice ships the minimal protocol and a mock that produces a stream.
- Whether `MediaTrack` needs more fields (codec, channel count) — defer until the player UI needs them (YAGNI).
- `finishedThreshold` default (`0.95`) — confirm during app polish; configurable via the init.

## 10. Spec reconciliation

Realizes §5.6 as written (the protocol's methods match). **Adds** the `PlaybackCoordinator` — shared resume/save logic that §5.6 left implicit in the app's play flow (§7); pulling it into the brain keeps Resume/Continue-Watching logic in one tested place. I'll note this in §5.6 when the slice lands.
