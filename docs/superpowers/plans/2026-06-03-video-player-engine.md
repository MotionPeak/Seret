# VideoPlayerEngine + PlaybackCoordinator — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `DebridCore` the playback seam — a `VideoPlayerEngine` protocol + playback value-type model that each app implements with VLCKit — and a `PlaybackCoordinator` that bridges playback to `WatchProgressStore` (resume on load, best-effort save, mark finished). This completes the brain.

**Architecture:** Pure value-type playback model. A `@MainActor`, class-bound `VideoPlayerEngine` protocol (VLCKit is UIKit-bound; the concrete engine ships per-app in Plan 7) exposing controls, track lists/selection, `addExternalSubtitle`, and an `AsyncStream<PlaybackEvent>`. A `Sendable`, stateless `PlaybackCoordinator` that reads/writes the existing `WatchProgressStore` — app-driven, so it's decoupled from the engine's callbacks and trivially testable.

**Tech Stack:** Swift 6.3 (Swift 6 language mode), SPM, `@MainActor` + `AsyncStream`, Swift Testing. No VLCKit / no UI in the package.

**Design spec:** [`docs/superpowers/specs/2026-06-03-video-player-engine-design.md`](../specs/2026-06-03-video-player-engine-design.md). Slice 3 of 3 of Plan 6 — completes the brain.

> **Conventions:** failing test → minimal impl → green → commit; small atomic `feat(core):`/`docs:` commits. Swift 6 value types + `Sendable`. **Zero warnings.** Run the **full** suite before each commit. The `PlaybackCoordinator` test uses SwiftData (via `WatchProgressStore`) → its suite MUST be `@Suite(.serialized)` (parallel-runner SIGSEGV gotcha; see CLAUDE.md). **Do not push** (owner pushes after review).

**Baseline:** 102 tests green on `main`.

## Existing pieces this builds on (confirmed)
`WatchProgressStore` (`@ModelActor public actor`, `Persistence/`): `func progress(forContentKey: String) throws -> WatchState?`, `func record(contentKey:sourceKey:positionSeconds:durationSeconds:finished:at: Date = Date()) throws`. `WatchState` (`Sendable`) has `positionSeconds: Double`, `finished: Bool`. In-memory test container: `WatchProgressStore(modelContainer: try ModelContainer(for: WatchProgress.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))`.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/DebridCore/Playback/PlaybackModel.swift` | `PlaybackState`, `PlaybackTime`, `TrackKind`, `MediaTrack`, `PlaybackEvent` |
| `Sources/DebridCore/Playback/VideoPlayerEngine.swift` | the `@MainActor` protocol |
| `Sources/DebridCore/Playback/PlaybackCoordinator.swift` | resume/save bridge to `WatchProgressStore` |
| `docs/superpowers/specs/2026-06-02-seret-design.md` (modify, Task 4) | §5.6 note re: the coordinator |
| `Tests/DebridCoreTests/…` | one test file per piece |

---

## Task 1: Playback model

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Playback/PlaybackModel.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/PlaybackModelTests.swift`

- [ ] **Step 1: Write the failing test** (pure — plain top-level suite)

`Tests/DebridCoreTests/PlaybackModelTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

@Suite struct PlaybackModelTests {
    @Test func statesAndEventsAreEquatable() {
        #expect(PlaybackState.failed("boom") == .failed("boom"))
        #expect(PlaybackState.playing != .paused)
        #expect(PlaybackEvent.time(PlaybackTime(position: 10, duration: 100))
                == .time(PlaybackTime(position: 10, duration: 100)))
        #expect(PlaybackEvent.state(.ended) != .state(.playing))
    }

    @Test func mediaTrackCarriesIdentityKindLanguage() {
        let track = MediaTrack(id: "a1", kind: .audio, name: "English", language: "en")
        #expect(track.id == "a1")
        #expect(track.kind == .audio)
        #expect(track.name == "English")
        #expect(track.language == "en")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter PlaybackModelTests`
Expected: FAIL to compile — `PlaybackState` / `MediaTrack` / etc. undefined.

- [ ] **Step 3: Implement the model**

`Sources/DebridCore/Playback/PlaybackModel.swift`:
```swift
import Foundation

/// The lifecycle of a playback session, as the engine reports it.
public enum PlaybackState: Sendable, Equatable {
    case idle, buffering, playing, paused, ended
    case failed(String)
}

/// The current playhead position and total duration, in seconds.
public struct PlaybackTime: Sendable, Equatable {
    public var position: Double
    public var duration: Double
    public init(position: Double, duration: Double) {
        self.position = position
        self.duration = duration
    }
}

public enum TrackKind: Sendable, Equatable {
    case audio, subtitle
}

/// A selectable audio or subtitle track surfaced by the engine.
public struct MediaTrack: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: TrackKind
    public let name: String
    public let language: String?
    public init(id: String, kind: TrackKind, name: String, language: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.language = language
    }
}

/// What the engine emits over time.
public enum PlaybackEvent: Sendable, Equatable {
    case state(PlaybackState)
    case time(PlaybackTime)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter PlaybackModelTests` → PASS (2). Full suite → **104 tests**. Zero warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): playback model (PlaybackState/Time/Track/Event)"
```

---

## Task 2: VideoPlayerEngine protocol (+ mock conformer test)

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Playback/VideoPlayerEngine.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/VideoPlayerEngineTests.swift`

**Context:** The protocol has no `DebridCore` consumer (the coordinator is independent), so a mock conformer in the test is what exercises it — proving it's implementable and ergonomic under `@MainActor` + `AsyncStream`.

- [ ] **Step 1: Write the failing test** (`@MainActor` suite; the mock conforms to the protocol and records calls)

`Tests/DebridCoreTests/VideoPlayerEngineTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

@MainActor
final class MockPlayerEngine: VideoPlayerEngine {
    private(set) var loaded: (url: URL, headers: [String: String])?
    private(set) var didPlay = false
    private(set) var didPause = false
    private(set) var seekedTo: Double?
    private(set) var selectedAudioID: String?
    private(set) var selectedSubtitleID: String?
    private(set) var externalSubtitle: URL?
    var audioTracks: [MediaTrack] = []
    var subtitleTracks: [MediaTrack] = []

    let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    init() {
        var c: AsyncStream<PlaybackEvent>.Continuation!
        events = AsyncStream { c = $0 }
        continuation = c
    }

    func load(url: URL, headers: [String: String]) { loaded = (url, headers) }
    func play() { didPlay = true; continuation.yield(.state(.playing)) }
    func pause() { didPause = true }
    func seek(to seconds: Double) { seekedTo = seconds }
    func selectAudioTrack(id: String?) { selectedAudioID = id }
    func selectSubtitleTrack(id: String?) { selectedSubtitleID = id }
    func addExternalSubtitle(url: URL) { externalSubtitle = url }
}

@Suite @MainActor struct VideoPlayerEngineTests {
    @Test func conformerRecordsControlCallsAndEmitsEvents() async {
        let engine = MockPlayerEngine()
        engine.subtitleTracks = [MediaTrack(id: "s1", kind: .subtitle, name: "Hebrew", language: "he")]

        engine.load(url: URL(string: "https://rd/x.mkv")!, headers: ["Authorization": "Bearer T"])
        engine.seek(to: 42)
        engine.selectSubtitleTrack(id: "s1")
        engine.addExternalSubtitle(url: URL(fileURLWithPath: "/tmp/x.srt"))
        engine.play()

        #expect(engine.loaded?.url.absoluteString == "https://rd/x.mkv")
        #expect(engine.loaded?.headers["Authorization"] == "Bearer T")
        #expect(engine.seekedTo == 42)
        #expect(engine.selectedSubtitleID == "s1")
        #expect(engine.externalSubtitle?.path == "/tmp/x.srt")
        #expect(engine.subtitleTracks.first?.language == "he")
        #expect(engine.didPlay == true)

        // the protocol's event stream delivers what the engine emitted (buffered before consumption)
        var first: PlaybackEvent?
        for await event in engine.events { first = event; break }
        #expect(first == .state(.playing))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter VideoPlayerEngineTests`
Expected: FAIL to compile — `VideoPlayerEngine` undefined.

- [ ] **Step 3: Implement the protocol**

`Sources/DebridCore/Playback/VideoPlayerEngine.swift`:
```swift
import Foundation

/// The playback seam. Implemented per app target with VLCKit (`TVVLCKit` / `MobileVLCKit`); the
/// `@MainActor`, class-bound shape matches a UIKit-bound player. `DebridCore` owns only this
/// interface + the playback model — no VLCKit here. The seam also lets Stage 3 add an AVPlayer
/// fast-path behind the same protocol.
@MainActor
public protocol VideoPlayerEngine: AnyObject {
    /// Load a direct (unrestricted) media URL. `headers` are passed to the underlying player
    /// (e.g. an `Authorization` header if a source ever needs one).
    func load(url: URL, headers: [String: String])
    func play()
    func pause()
    func seek(to seconds: Double)

    var audioTracks: [MediaTrack] { get }
    var subtitleTracks: [MediaTrack] { get }
    func selectAudioTrack(id: String?)
    func selectSubtitleTrack(id: String?)   // nil = off
    func addExternalSubtitle(url: URL)       // a downloaded subtitle temp-file URL (slice 2)

    /// Time + state updates as the engine produces them.
    var events: AsyncStream<PlaybackEvent> { get }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter VideoPlayerEngineTests` → PASS (1). Full suite → **105 tests**. Zero warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): VideoPlayerEngine protocol (@MainActor playback seam)"
```

---

## Task 3: PlaybackCoordinator

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Playback/PlaybackCoordinator.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/PlaybackCoordinatorTests.swift`

- [ ] **Step 1: Write the failing tests** (SwiftData via `WatchProgressStore` → suite MUST be `@Suite(.serialized)`)

`Tests/DebridCoreTests/PlaybackCoordinatorTests.swift`:
```swift
import Testing
import Foundation
import SwiftData
@testable import DebridCore

@Suite(.serialized) struct PlaybackCoordinatorTests {
    private func store() throws -> WatchProgressStore {
        let container = try ModelContainer(
            for: WatchProgress.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return WatchProgressStore(modelContainer: container)
    }

    @Test func resumeIsZeroWhenNoProgress() async throws {
        let coord = PlaybackCoordinator(store: try store())
        #expect(await coord.resumePosition(contentKey: "movie:tmdb:1") == 0)
    }

    @Test func recordThenResumeReturnsSavedPosition() async throws {
        let s = try store()
        let coord = PlaybackCoordinator(store: s)
        await coord.record(contentKey: "movie:tmdb:1", sourceKey: "T#0", position: 73, duration: 100)
        #expect(await coord.resumePosition(contentKey: "movie:tmdb:1") == 73)
        let saved = try await s.progress(forContentKey: "movie:tmdb:1")
        #expect(saved?.positionSeconds == 73)
        #expect(saved?.finished == false)
    }

    @Test func recordMarksFinishedPastThreshold() async throws {
        let s = try store()
        let coord = PlaybackCoordinator(store: s)
        await coord.record(contentKey: "k", sourceKey: "T#0", position: 96, duration: 100)   // 96% ≥ 95%
        #expect(try await s.progress(forContentKey: "k")?.finished == true)
    }

    @Test func recordBelowThresholdIsNotFinished() async throws {
        let s = try store()
        let coord = PlaybackCoordinator(store: s)
        await coord.record(contentKey: "k", sourceKey: "T#0", position: 50, duration: 100)
        #expect(try await s.progress(forContentKey: "k")?.finished == false)
    }

    @Test func resumeIsZeroWhenFinished() async throws {
        let s = try store()
        let coord = PlaybackCoordinator(store: s)
        await coord.record(contentKey: "k", sourceKey: "T#0", position: 99, duration: 100)   // finished
        #expect(await coord.resumePosition(contentKey: "k") == 0)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter PlaybackCoordinatorTests`
Expected: FAIL to compile — `PlaybackCoordinator` undefined.

- [ ] **Step 3: Implement the coordinator**

`Sources/DebridCore/Playback/PlaybackCoordinator.swift`:
```swift
import Foundation

/// Bridges playback to `WatchProgressStore`: where to resume a title, and saving progress as it
/// plays. Stateless and `Sendable` — the app drives it (calls `record` on a timer / pause /
/// background), so throttling lives in the app and the coordinator stays decoupled from the
/// engine's callbacks. Saves are best-effort: a store error never interrupts playback.
public struct PlaybackCoordinator: Sendable {
    private let store: WatchProgressStore
    private let finishedThreshold: Double

    public init(store: WatchProgressStore, finishedThreshold: Double = 0.95) {
        self.store = store
        self.finishedThreshold = finishedThreshold
    }

    /// The position to resume a title from — `0` if there's no saved progress, the title is
    /// already finished, or the lookup fails.
    public func resumePosition(contentKey: String) async -> Double {
        guard let state = (try? await store.progress(forContentKey: contentKey)) ?? nil,
              !state.finished else { return 0 }
        return state.positionSeconds
    }

    /// Persist the current position (best-effort), marking the title finished once
    /// `position / duration >= finishedThreshold`.
    public func record(contentKey: String, sourceKey: String,
                       position: Double, duration: Double) async {
        let finished = duration > 0 && position / duration >= finishedThreshold
        try? await store.record(contentKey: contentKey, sourceKey: sourceKey,
                                positionSeconds: position, durationSeconds: duration,
                                finished: finished)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter PlaybackCoordinatorTests` → PASS (5). Then the full suite → **110 tests**, run **twice** for stability. Zero warnings (`swift build --package-path Packages/DebridCore 2>&1 | grep -i warning` empty).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): PlaybackCoordinator — resume + best-effort save via WatchProgressStore"
```

---

## Task 4: Reconcile the design spec §5.6 (documentation)

**Files:**
- Modify: `docs/superpowers/specs/2026-06-02-seret-design.md`

> No test — documentation only.

- [ ] **Step 1: Patch §5.6** "Playback" to note that `DebridCore` now also ships a **`PlaybackCoordinator`** (the resume/best-effort-save bridge to `WatchProgressStore`, marking finished at ~95%) alongside the `VideoPlayerEngine` protocol + playback model — keeping Resume/Continue-Watching logic in the shared brain rather than per app. Point to [`2026-06-03-video-player-engine-design.md`](docs/superpowers/specs/2026-06-03-video-player-engine-design.md). Leave the rest of §5.6 intact.

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-06-02-seret-design.md
git commit -m "docs(spec): note PlaybackCoordinator in §5.6 (shared resume/save bridge)"
```

---

## Done when

- [ ] `swift test --package-path Packages/DebridCore` green (**110 tests**), stable across two runs, zero warnings.
- [ ] `DebridCore` exposes: the playback model (`PlaybackState`/`PlaybackTime`/`TrackKind`/`MediaTrack`/`PlaybackEvent`), the `@MainActor VideoPlayerEngine` protocol, and `PlaybackCoordinator` (`resumePosition` / `record`).
- [ ] The coordinator resumes the saved position (0 when none/finished) and saves best-effort, marking finished at the threshold; its suite is `@Suite(.serialized)`.
- [ ] No VLCKit / UI imported in the package. §5.6 reconciled. All work committed (not pushed).

> **Consumer-side (Plan 7 / the app):** the concrete VLCKit engine conforming to `VideoPlayerEngine`, the SwiftUI player view, wiring `engine.events` → throttled `coordinator.record(...)`, and deriving `contentKey`/`sourceKey` via `WatchKey`.

**The brain is now feature-complete.** Next: **Plan 7** — the Apple TV app (the first UI: XcodeGen + VLCKit + a real TMDB/OpenSubtitles key), which implements `VideoPlayerEngine` and consumes `LibraryService` / `WatchProgressStore` / `OpenSubtitlesProvider` / `PlaybackCoordinator`.
