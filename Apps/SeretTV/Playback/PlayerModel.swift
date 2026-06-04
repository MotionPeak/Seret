import Observation
import Foundation
import DebridCore

/// Orchestrates a single playback session: unrestrict → load → resume → play,
/// engine-state→Phase mapping, throttled progress-save, end-of-playback, and teardown.
/// Injected via closures + seams so the full lifecycle is unit-testable without VLCKit.
@MainActor
@Observable
final class PlayerModel {

    // MARK: - Phase

    enum Phase: Equatable {
        case preparing
        case buffering
        case playing
        case paused
        case ended
        case failed(String)
    }

    // MARK: - Subtitle state

    enum SubtitleRowState: Equatable {
        case idle
        case downloading
        case attached(String)
        case capReached(Date?)
        case error
        case noAccount
    }

    struct SubtitleRow: Identifiable, Equatable {
        let language: String
        var state: SubtitleRowState
        var id: String { language }
    }

    // MARK: - Published state

    private(set) var phase: Phase = .preparing
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    var controlsVisible: Bool = true
    private(set) var audioTracks: [MediaTrack] = []
    private(set) var subtitleTracks: [MediaTrack] = []
    private(set) var subtitleRows: [SubtitleRow]
    private(set) var shouldDismiss: Bool = false

    // MARK: - Stored properties

    private let item: MediaItem
    private let sources: [MediaSource]
    private var sourceIndex: Int = 0
    private let resumeAt: Double?
    let label: String
    private let engine: VideoPlayerEngine
    private let unrestrict: (String) async throws -> URL
    private let recordProgress: (Double, Double) async -> Void
    private let subtitles: SubtitleProvider?

    private var eventTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var lastSavedPosition: Double = -.infinity
    private let saveInterval: Double = 5

    // MARK: - Computed helpers

    var canTryAnotherVersion: Bool { sourceIndex + 1 < sources.count }
    var currentSource: MediaSource { sources[sourceIndex] }

    // MARK: - Init

    init(request: PlaybackRequest,
         engine: VideoPlayerEngine,
         unrestrict: @escaping (String) async throws -> URL,
         recordProgress: @escaping (Double, Double) async -> Void,
         subtitles: SubtitleProvider?) {
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
    func start() {
        eventTask?.cancel()
        eventTask = Task { await self.consumeEvents() }
        reload()
    }

    private func consumeEvents() async {
        for await event in engine.events {
            switch event {
            case .state(let s): handle(state: s)
            case .time(let t): await tick(t)
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
            phase = .buffering
        case .playing:
            phase = .playing
            audioTracks = engine.audioTracks
            subtitleTracks = engine.subtitleTracks
        case .paused:
            phase = .paused
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
            audioTracks = engine.audioTracks
            subtitleTracks = engine.subtitleTracks
        }
        if position - lastSavedPosition >= saveInterval {
            lastSavedPosition = position
            await recordProgress(position, duration)
        }
    }

    private func finish() async {
        guard phase != .ended else { return }   // VLCKit can emit .stopped + .ended; finish once
        await recordProgress(position, duration)
        phase = .ended
        shouldDismiss = true
    }

    // MARK: - Transport controls

    func togglePlayPause() {
        if phase == .playing { engine.pause() } else { engine.play() }
    }

    func skip(_ delta: Double) { engine.seek(to: max(0, position + delta)) }
    func scrub(to seconds: Double) { engine.seek(to: seconds) }

    func selectSubtitle(id: String) { engine.selectSubtitleTrack(id: id) }
    func selectSubtitleOff() { engine.selectSubtitleTrack(id: nil) }
    func selectAudio(id: String) { engine.selectAudioTrack(id: id) }

    // MARK: - Teardown

    func teardown() async {
        eventTask?.cancel()
        loadTask?.cancel()
        await recordProgress(position, duration)
        engine.stop()
    }

    // MARK: - Recovery

    func retry() { reload() }

    func tryAnotherVersion() {
        guard sourceIndex + 1 < sources.count else { return }
        sourceIndex += 1
        reload()
    }

    // MARK: - Subtitles

    func requestSubtitle(language: String) async {
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
    func waitForIdleForTesting() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}
