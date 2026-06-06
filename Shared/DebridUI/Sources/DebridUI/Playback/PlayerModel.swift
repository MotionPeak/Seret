import Observation
import Foundation
import DebridCore

/// Orchestrates a single playback session: unrestrict → load → resume → play,
/// engine-state→Phase mapping, throttled progress-save, end-of-playback, and teardown.
/// Injected via closures + seams so the full lifecycle is unit-testable without VLCKit.
@MainActor
@Observable
public final class PlayerModel {

    // MARK: - Phase

    public enum Phase: Equatable {
        case preparing
        case buffering
        case playing
        case paused
        case ended
        case failed(String)
    }

    // MARK: - Subtitle state

    public enum SubtitleRowState: Equatable {
        case idle
        case downloading
        case attached(String)
        case capReached(Date?)
        case error
        case noAccount
    }

    public struct SubtitleRow: Identifiable, Equatable {
        public let language: String
        public var state: SubtitleRowState
        public var id: String { language }
    }

    // MARK: - Published state

    public private(set) var phase: Phase = .preparing
    public private(set) var position: Double = 0
    public private(set) var duration: Double = 0
    public private(set) var controlsVisible: Bool = true
    public private(set) var audioTracks: [MediaTrack] = []
    public private(set) var subtitleTracks: [MediaTrack] = []
    public private(set) var subtitleRows: [SubtitleRow]
    public private(set) var shouldDismiss: Bool = false

    /// Continuous swipe-scrub (Step 2). While `isScrubbing`, the transport shows a preview marker at
    /// `scrubTarget` instead of the live playhead; the seek only happens on `commitScrub()`.
    public private(set) var isScrubbing: Bool = false
    public private(set) var scrubTarget: Double = 0
    /// Whether the (UIKit-focusable) scrub surface holds focus — drives the bar's focused look.
    public private(set) var scrubberFocused: Bool = false
    /// Whether the thin scrub bar should be on screen (sticky for `scrubBarDwell` seconds after the
    /// last interaction). Distinct from `isScrubbing` (mid-gesture only).
    public private(set) var scrubBarVisible: Bool = false

    // MARK: - Stored properties

    private let item: MediaItem
    private let sources: [MediaSource]
    private var sourceIndex: Int = 0
    private let resumeAt: Double?
    public let label: String
    private let engine: VideoPlayerEngine
    private let unrestrict: (String) async throws -> URL
    private let recordProgress: (Double, Double) async -> Void
    private let subtitles: SubtitleProvider?

    private var eventTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var hideControlsTask: Task<Void, Never>?
    private var scrubBarHideTask: Task<Void, Never>?
    private var lastSavedPosition: Double = -.infinity
    private let saveInterval: Double = 5
    private let autoHideDelay: Double
    private let scrubBarDwell: Double = 5      // bar stays visible for 5s after the last interaction

    // MARK: - Computed helpers

    public var canTryAnotherVersion: Bool { sourceIndex + 1 < sources.count }
    public var currentSource: MediaSource { sources[sourceIndex] }

    // MARK: - Init

    public init(request: PlaybackRequest,
         engine: VideoPlayerEngine,
         unrestrict: @escaping (String) async throws -> URL,
         recordProgress: @escaping (Double, Double) async -> Void,
         subtitles: SubtitleProvider?,
         autoHideDelay: Double = 4) {
        self.autoHideDelay = autoHideDelay
        self.item = request.item
        // Preferred source first, then remaining sources in quality order (deduped).
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

    // MARK: - Lifecycle

    /// Called once when the player appears. Starts the long-lived event loop (the single consumer of
    /// the engine's AsyncStream) and loads the first source. retry()/tryAnotherVersion() re-load
    /// WITHOUT relaunching the loop, so the single VLCKit stream is consumed continuously across
    /// source switches.
    public func start() {
        eventTask?.cancel()
        eventTask = Task { await self.consumeEvents() }
        reload()
    }

    private func consumeEvents() async {
        for await event in engine.events {
            switch event {
            case .state(let s): handle(state: s)
            case .time(let t): await tick(t)
            case .tracksChanged: refreshTracks()
            }
        }
    }

    private func reload() {
        phase = .preparing
        position = 0
        duration = 0
        lastSavedPosition = -.infinity
        loadTask?.cancel()
        loadTask = Task { await self.loadCurrentSource() }
    }

    private func loadCurrentSource() async {
        do {
            let url = try await unrestrict(currentSource.restrictedLink)
            guard !Task.isCancelled else { return }   // superseded by a newer reload()
            engine.load(url: url, headers: [:])
            if let resumeAt, resumeAt > 0 { engine.seek(to: resumeAt) }
            engine.play()
        } catch is CancellationError {
            return                                       // superseded; not a real failure
        } catch {
            phase = .failed("The Real-Debrid link could not be opened.")
        }
    }

    private func handle(state: PlaybackState) {
        switch state {
        case .idle, .buffering:
            // VLCKit emits .buffering even after playback has started; don't let it revert an
            // active session (that caused the loading overlay to flicker over the video at start).
            if phase != .playing && phase != .paused { phase = .buffering }
        case .playing:
            phase = .playing
            refreshTracks()
            armAutoHide()
        case .paused:
            phase = .paused
            controlsVisible = true            // a paused viewer is looking — keep controls up
            hideControlsTask?.cancel()
        case .ended:
            Task { await finish() }
        case .failed(let reason):
            phase = .failed(reason)
        }
    }

    private func tick(_ t: PlaybackTime) async {
        position = t.position
        duration = t.duration
        // VLCKit can sit in `.buffering` (or never emit a clean `.playing`) while it is
        // actually rendering frames. The playhead moving is the reliable "we're playing"
        // signal — promote out of the loading overlay so working playback isn't hidden
        // behind "Buffering…".
        if t.position > 0, phase == .buffering || phase == .preparing {
            phase = .playing
            refreshTracks()
            armAutoHide()
        }
        if position - lastSavedPosition >= saveInterval {
            lastSavedPosition = position
            await recordProgress(position, duration)
        }
    }

    /// Pull the engine's current track lists into the published state. Called when playback starts
    /// and on every `.tracksChanged` event (VLCKit discovers elementary streams asynchronously, and
    /// an on-demand external subtitle appears after load).
    private func refreshTracks() {
        audioTracks = engine.audioTracks
        subtitleTracks = engine.subtitleTracks
    }

    private func finish() async {
        guard phase != .ended else { return }   // VLCKit can emit .stopped + .ended; finish once
        await recordProgress(position, duration)
        phase = .ended
        shouldDismiss = true
    }

    // MARK: - Transport controls

    public func togglePlayPause() {
        if phase == .playing { engine.pause() } else { engine.play() }
        revealScrubBar()
    }

    /// Reveal the thin scrub bar and re-arm a 5s sticky timer. Called on every player interaction
    /// (click, swipe, commit). Cancels any pending hide; PlayerView fades it in/out.
    public func revealScrubBar() {
        scrubBarVisible = true
        scrubBarHideTask?.cancel()
        scrubBarHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(scrubBarDwell))
            guard !Task.isCancelled, !isScrubbing else { return }
            scrubBarVisible = false
        }
    }

    public func skip(_ delta: Double) { engine.seek(to: max(0, position + delta)) }
    public func scrub(to seconds: Double) { engine.seek(to: seconds) }

    /// Playback rate multiplier (1 = normal). Settings panel uses 0.5/0.75/1/1.25/1.5.
    public private(set) var playbackSpeed: Double = 1
    public func setPlaybackSpeed(_ rate: Double) {
        playbackSpeed = rate
        engine.setRate(rate)
    }

    // MARK: - Swipe-scrub (Step 2)

    /// Enter scrub mode (a select press on the focused bar). The preview marker starts at the
    /// playhead; the user then swipes to glide it and presses again to seek. Controls stay up.
    public func beginScrub() {
        scrubTarget = position
        isScrubbing = true
        controlsVisible = true
        hideControlsTask?.cancel()            // never auto-hide mid-scrub
        scrubBarHideTask?.cancel()
        scrubBarVisible = true
    }

    /// Move the preview marker by `deltaSeconds`, clamped to the media's bounds. No seek yet.
    public func updateScrub(by deltaSeconds: Double) {
        guard isScrubbing else { return }
        let upper = duration > 0 ? duration : scrubTarget + max(0, deltaSeconds)
        scrubTarget = min(max(0, scrubTarget + deltaSeconds), upper)
    }

    /// Seek to the preview marker and leave scrub mode. Optimistically advance the playhead so the
    /// bar doesn't snap back to the old position before the engine reports the new time.
    public func commitScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        position = scrubTarget
        engine.seek(to: scrubTarget)
        armAutoHide()
        revealScrubBar()                       // sticky 5s after commit
    }

    /// Abandon scrub mode without seeking (the playhead is untouched).
    public func cancelScrub() {
        isScrubbing = false
        armAutoHide()
        revealScrubBar()
    }

    // MARK: - Controls auto-hide

    /// Reveal the transport and re-arm the auto-hide timer. Called on every user interaction.
    public func showControls() {
        controlsVisible = true
        armAutoHide()
    }

    /// Touch tap-to-toggle: hide the transport if it's up, else reveal it (and re-arm auto-hide).
    public func toggleControls() {
        if controlsVisible {
            controlsVisible = false
            hideControlsTask?.cancel()
        } else {
            showControls()
        }
    }

    /// The UIKit scrub surface gained/lost focus. Keep the controls up while it's focused.
    public func setScrubberFocused(_ focused: Bool) {
        scrubberFocused = focused
        if focused { showControls() }
    }

    /// Hide the transport after `autoHideDelay` of no interaction — but only while actively playing
    /// and not scrubbing (paused / buffering / error keep the controls up).
    private func armAutoHide() {
        hideControlsTask?.cancel()
        guard autoHideDelay > 0 else { return }
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(autoHideDelay))
            guard !Task.isCancelled else { return }
            if phase == .playing, !isScrubbing { controlsVisible = false }
        }
    }

    public func selectSubtitle(id: String) { engine.selectSubtitleTrack(id: id) }
    public func selectSubtitleOff() { engine.selectSubtitleTrack(id: nil) }
    public func selectAudio(id: String) { engine.selectAudioTrack(id: id) }

    // MARK: - Teardown

    public func teardown() async {
        eventTask?.cancel()
        loadTask?.cancel()
        hideControlsTask?.cancel()
        scrubBarHideTask?.cancel()
        await recordProgress(position, duration)
        engine.stop()
    }

    // MARK: - Recovery

    public func retry() { reload() }

    public func tryAnotherVersion() {
        guard sourceIndex + 1 < sources.count else { return }
        sourceIndex += 1
        reload()
    }

    // MARK: - Subtitles

    public func requestSubtitle(language: String) async {
        guard let subtitles else { setRow(language, .noAccount); return }
        guard subtitleRows.first(where: { $0.language == language })?.state != .downloading else { return }
        setRow(language, .downloading)
        do {
            let query = SubtitleQuery.movie(item)
            let results = try await subtitles.search(query, languages: [language])
            guard let best = results.first else { setRow(language, .error); return }
            let url = try await subtitles.download(best)
            let before = Set(engine.subtitleTracks.map(\.id))
            engine.addExternalSubtitle(url: url)
            subtitleTracks = engine.subtitleTracks
            let newID = subtitleTracks.first(where: { !before.contains($0.id) })?.id
            engine.selectSubtitleTrack(id: newID)
            setRow(language, .attached(newID ?? language))
        } catch let SubtitleError.dailyCapReached(reset) {
            setRow(language, .capReached(reset))
        } catch SubtitleError.notAuthenticated {
            setRow(language, .noAccount)
        } catch {
            setRow(language, .error)
        }
    }

    private func setRow(_ language: String, _ state: SubtitleRowState) {
        guard let i = subtitleRows.firstIndex(where: { $0.language == language }) else { return }
        subtitleRows[i].state = state
    }

    // MARK: - Test hook

    /// Yields the current task so in-flight async work can complete before assertions.
    /// Used only in unit tests — see `PlayerModelTests`.
    public func waitForIdleForTesting() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}
