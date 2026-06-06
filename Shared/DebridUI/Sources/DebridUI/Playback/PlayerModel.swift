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

    /// Currently-selected track ids — drives the settings sheet's selection indicator.
    public private(set) var selectedAudioID: String?
    public private(set) var selectedSubtitleID: String?   // nil = Off

    /// Continuous swipe-scrub (Step 2). While `isScrubbing`, the transport shows a preview marker at
    /// `scrubTarget` instead of the live playhead; the seek only happens on `commitScrub()`.
    public private(set) var isScrubbing: Bool = false
    public private(set) var scrubTarget: Double = 0
    /// Whether the (UIKit-focusable) scrub surface holds focus — drives the bar's focused look.
    public private(set) var scrubberFocused: Bool = false
    /// Whether the thin scrub bar should be on screen (sticky for `scrubBarDwell` seconds after the
    /// last interaction). Distinct from `isScrubbing` (mid-gesture only).
    public private(set) var scrubBarVisible: Bool = false

    /// First real video frame has rendered for the current source (sustained time advance or a real
    /// `.playing`). Gates the full-screen loading overlay so it never hides over a still-black
    /// picture.
    public private(set) var hasRenderedFrame: Bool = false
    /// Waiting on frames — initial load, a skip/seek, or a mid-stream rebuffer. Drives the loading
    /// indicator (full overlay before the first frame; a small inline hint after).
    public private(set) var isBuffering: Bool = true

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
    /// Last engine-reported position — to detect *sustained* advance (real frames) vs a single
    /// echoed seek tick.
    private var lastTickPosition: Double = 0
    /// Resume: where to seek to once playback starts (0 = none) and whether that seek has fired. A
    /// deferred seek (not a load-time start-time) keeps the whole timeline seekable.
    private var resumeTarget: Double = 0
    private var resumeSeekIssued: Bool = false
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
        hasRenderedFrame = false
        isBuffering = true
        lastTickPosition = 0
        resumeTarget = (resumeAt ?? 0) > 0 ? (resumeAt ?? 0) : 0   // >0 → deferred-seek there once playing
        resumeSeekIssued = false
        lastSavedPosition = -.infinity
        loadTask?.cancel()
        loadTask = Task { await self.loadCurrentSource() }
    }

    private func loadCurrentSource() async {
        do {
            let url = try await unrestrict(currentSource.restrictedLink)
            guard !Task.isCancelled else { return }   // superseded by a newer reload()
            engine.load(url: url, headers: [:])
            engine.play()
            // Resume is a DEFERRED seek (issued from tick() once playback starts), not a load-time
            // start-time: a start-time clips the timeline so you can't rewind before the point.
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
            // active session's phase (that flashed the overlay over the video). It does mean we're
            // waiting on frames — flag buffering so the UI shows a small inline hint (the full
            // overlay only shows before the first frame).
            isBuffering = true
            if phase != .playing && phase != .paused { phase = .buffering }
        case .playing:
            phase = .playing
            markRendered()
            refreshTracks()
            armAutoHide()
        case .paused:
            phase = .paused
            isBuffering = false
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

        // Resume: a tick means VLCKit has parsed the media and will honor a seek, so issue the
        // resume seek ONCE here, then keep the loading overlay up until the playhead actually
        // reaches the point — the bar never flashes 0 and jumps, and the full timeline stays
        // seekable (a load-time start-time would clip it: no rewinding before the point).
        if resumeTarget > 0 {
            if !resumeSeekIssued {
                engine.seek(to: resumeTarget)
                resumeSeekIssued = true
            }
            if t.position >= resumeTarget - 5 {        // arrived (keyframe slack) → resume complete
                lastTickPosition = t.position
                resumeTarget = 0
            }
            return                                      // overlay stays; no promote/save while seeking
        }

        // Sustained advance past the last tick = the decoder is really producing frames. A single
        // tick at the seek target is not advance, so the overlay stays until the picture is moving.
        let advanced = t.position > lastTickPosition + 0.05
        lastTickPosition = t.position
        if advanced {
            markRendered()
            if phase == .buffering || phase == .preparing {
                phase = .playing
                refreshTracks()
                armAutoHide()
            }
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

    /// First frames are on screen. Clears the loading state so the overlay/spinner hide.
    private func markRendered() {
        hasRenderedFrame = true
        isBuffering = false
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

    public func skip(_ delta: Double) {
        let target = clamp(position + delta)
        position = target            // optimistic: the scrub bar jumps to the new time immediately
        isBuffering = true           // …and shows the loading hint while the seek rebuffers
        lastTickPosition = target    // re-arm advance detection past the target
        engine.seek(to: target)
    }
    public func scrub(to seconds: Double) { engine.seek(to: clamp(seconds)) }

    /// Clamp a time to `[0, duration]` (duration may be 0 before it is known).
    private func clamp(_ t: Double) -> Double {
        let upper = duration > 0 ? duration : max(0, t)
        return min(max(0, t), upper)
    }

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
        lastTickPosition = scrubTarget
        isBuffering = true                     // loading hint while the seek rebuffers
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

    public func selectSubtitle(id: String) { selectedSubtitleID = id; engine.selectSubtitleTrack(id: id) }
    public func selectSubtitleOff() { selectedSubtitleID = nil; engine.selectSubtitleTrack(id: nil) }
    public func selectAudio(id: String) { selectedAudioID = id; engine.selectAudioTrack(id: id) }

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
            selectedSubtitleID = newID
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
