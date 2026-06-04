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
    private var lastSavedPosition: Double = -.infinity
    private let saveInterval: Double = 5

    // MARK: - Computed helpers

    var canTryAnotherVersion: Bool { sources.count > 1 }
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

    // MARK: - Teardown

    func teardown() async {
        eventTask?.cancel()
        await recordProgress(position, duration)
    }

    // MARK: - Test hook

    /// Yields the current task so in-flight async work can complete before assertions.
    /// Used only in unit tests — see `PlayerModelTests`.
    func waitForIdleForTesting() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}
