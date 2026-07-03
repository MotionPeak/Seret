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

    /// "Up Next" bar state (shows near content-end for a show with another episode).
    public private(set) var upNextVisible: Bool = false
    public private(set) var upNextSecondsRemaining: Int = 0

    /// Currently-selected track ids — drives the settings sheet's selection indicator.
    public private(set) var selectedAudioID: String?
    public private(set) var selectedSubtitleID: String?   // nil = Off

    /// A finished subtitle download waiting for VLCKit to actually attach the slave track — it
    /// appears asynchronously via `.tracksChanged`, not synchronously after `addExternalSubtitle`.
    /// `before` is the text-track id set captured just before the attach, so the freshly-appeared
    /// id is the one not in it. Resolved in `refreshTracks()`.
    private var pendingSubtitleAttach: (language: String, before: Set<String>)?

    /// Subtitle tracks to show as plain pills — EXCLUDES on-demand downloads, which are
    /// represented by their language row instead. Without this, a downloaded "Hebrew" sub also
    /// shows up as a generic "Track N" pill (the duplicate the user reported).
    public var embeddedSubtitleTracks: [MediaTrack] {
        let downloaded = downloadedTrackIDs
        return subtitleTracks.filter { !downloaded.contains($0.id) }
    }

    /// Track ids that came from an on-demand subtitle download (one per `.attached` row).
    private var downloadedTrackIDs: Set<String> {
        Set(subtitleRows.compactMap { attachedTrackID($0) })
    }

    /// The downloaded track id backing a language row, if it has been downloaded.
    public func attachedTrackID(_ row: SubtitleRow) -> String? {
        if case .attached(let id) = row.state { return id } else { return nil }
    }

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
    private var sources: [MediaSource]
    private var sourceIndex: Int = 0
    private var resumeAt: Double?
    public private(set) var label: String
    /// The episode currently playing (shows only) and the WatchKey it records progress under.
    /// Both change when we advance to the next episode in-place.
    private var episode: Episode?
    private var contentKey: String
    private let engine: VideoPlayerEngine
    private let unrestrict: (String) async throws -> URL
    /// Authoritative resume lookup (contentKey → saved seconds, nil/0 = start). Resolved at LOAD
    /// time so playback always resumes from the store's truth — the screen's watch state can be
    /// not-yet-loaded (tap Play right after Detail opens) or stale (immediate re-play) when the
    /// request was built. Also what lets retry/try-another-version resume where playback failed.
    private let resolveResume: ((String) async -> Double?)?
    /// Fire-and-forget unrestrict warm-up (PlayableLinkCache.prefetch) — called for the next
    /// episode's link when the Up Next bar appears, so a binge auto-advance starts instantly.
    private let prefetchLink: ((String) -> Void)?
    /// "Start over" was explicitly chosen for the initial request — never resume it. Cleared on
    /// an episode switch (the provider decides for the new episode).
    private var fromStart: Bool
    /// Records progress for the *currently playing* content — PlayerModel passes the live
    /// contentKey + sourceKey so next-episode advances record under the right keys.
    private let recordProgress: (_ contentKey: String, _ sourceKey: String, _ position: Double, _ duration: Double) async -> Void
    private let subtitles: SubtitleProvider?
    /// On-demand TMDB episode metadata (names + stills) for the in-player episode strip. Optional —
    /// when nil (or for a movie) the strip simply carries no names/thumbnails.
    private let details: MediaDetailsProviding?
    /// App-global preferred audio/subtitle language. Recorded on a manual pick and auto-applied once
    /// per loaded source. Optional — nil disables persistence (no preference recorded or applied).
    private let trackPreferences: TrackPreferenceStoring?
    /// Whether the preferred tracks have been auto-applied for the current source (reset on reload),
    /// so a later manual change isn't reverted by subsequent `.tracksChanged` events.
    private var trackPrefsApplied = false

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
    /// A manual seek (skip/commitScrub) in flight: `to` is the optimistic target the bar already
    /// shows, `from` the pre-seek playhead. While set, `tick()` ignores VLCKit's stale pre-seek
    /// time echoes (which would snap the bar back) until a tick arrives nearer `to` than `from`.
    private var pendingSeek: (from: Double, to: Double)?
    /// True from the moment we swap episodes until the new media renders its first frame. The OLD
    /// media can emit a late `.ended` during that window; this flag makes `finish()` swallow it so a
    /// stale end can't auto-advance/exit a second time (the "it keeps jumping/restarting" bug).
    private var isSwitching = false
    private let saveInterval: Double = 5
    private let autoHideDelay: Double
    private let scrubBarDwell: Double = 5      // bar stays visible for 5s after the last interaction

    /// Engine-seek coalescing for skip bursts: the first skip seeks immediately (instant
    /// response); further skips inside the window only move the target and ONE trailing seek
    /// fires at the final target — four fast double-taps become two engine seeks, not four
    /// full seek+rebuffer cycles.
    private let seekCoalesceWindow: Double
    private var seekDispatchTask: Task<Void, Never>?
    private var coalescedSeekTarget: Double?
    private var dispatchedSeekTarget: Double?

    // MARK: - Up Next (binge)
    /// Last subtitle cue (seconds), when a sub was downloaded. A FLOOR for the Up Next bar — it
    /// won't fire while a line is still being spoken — but no longer triggers it directly (the last
    /// line is often well before the credits). nil → use the credits-lead estimate alone.
    private var contentEndTime: Double?
    private var upNextDismissed = false
    private var upNextTask: Task<Void, Never>?
    private let upNextCountdownStart = 10
    /// The credits are roughly the last ~30s of the file. The countdown should roll DURING the
    /// credits, so the bar appears no earlier than this before the end — never at the last spoken
    /// line (which is often well before the credits) nor during dialogue that runs late.
    private let upNextCreditsLead: Double = 30

    /// When the "Up Next" bar should appear (nil → never, e.g. no next episode or a too-short file).
    /// The LATER of the last subtitle cue and a credits-length before the end — so it lands in the
    /// credits, not the final scene — clamped so the 10s countdown still finishes before the file end.
    private var upNextThreshold: Double? {
        guard hasNextEpisode, duration > Double(upNextCountdownStart) + 6 else { return nil }
        let creditsStart = max(contentEndTime ?? 0, duration - upNextCreditsLead)
        return min(creditsStart, duration - Double(upNextCountdownStart) - 2)
    }

    // MARK: - Computed helpers

    public var canTryAnotherVersion: Bool { sourceIndex + 1 < sources.count }
    public var currentSource: MediaSource { sources[sourceIndex] }

    /// The next episode in series order after the one playing, if any. `nil` for movies, for the
    /// last episode, or when the item carries no season data (e.g. an Add-flow play).
    public var nextEpisode: Episode? {
        guard let episode else { return nil }
        let ordered = item.seasons
            .sorted { $0.number < $1.number }
            .flatMap { $0.episodes.sorted { $0.number < $1.number } }
        guard let i = ordered.firstIndex(where: { $0.season == episode.season && $0.number == episode.number }),
              i + 1 < ordered.count else { return nil }
        return ordered[i + 1]
    }
    public var hasNextEpisode: Bool { nextEpisode != nil }

    /// True for a show episode (vs a movie) — gates the in-player episode strip.
    public var isEpisode: Bool { episode != nil }
    /// The episode currently playing (drives the strip's highlight). nil for a movie.
    public var currentEpisode: Episode? { episode }

    /// One row in the in-player season strip: a playable episode + its TMDB name/still.
    public struct PlayerEpisode: Identifiable, Equatable, Sendable {
        public let season: Int
        public let number: Int
        public let name: String?
        public let stillPath: String?
        /// The downloaded episode (playable) — nil when this episode isn't in the library yet.
        public let owned: Episode?
        public var id: String { "\(season)x\(number)" }
        public var isPlayable: Bool { owned != nil }
    }
    /// The current season's episodes for the strip (empty until `loadSeasonEpisodes()` runs).
    public private(set) var seasonEpisodes: [PlayerEpisode] = []

    /// Build the strip: the WHOLE current season from TMDB (so every episode shows, not just the
    /// downloaded ones), each tagged with its owned/playable episode when in the library. Falls
    /// back to owned-only if TMDB is unavailable. Shows only; no-op once loaded for this season.
    public func loadSeasonEpisodes() async {
        guard let episode else { return }
        if let first = seasonEpisodes.first, first.season == episode.season { return }
        let owned = item.seasons.first(where: { $0.number == episode.season })?.episodes ?? []
        let ownedByNumber = Dictionary(owned.map { ($0.number, $0) }, uniquingKeysWith: { a, _ in a })

        if let details, let tmdbID = item.tmdbID,
           let eps = try? await details.seasonEpisodes(tvID: tmdbID, season: episode.season), !eps.isEmpty {
            seasonEpisodes = eps.sorted { $0.episodeNumber < $1.episodeNumber }.map { e in
                PlayerEpisode(season: episode.season, number: e.episodeNumber,
                              name: e.name, stillPath: e.stillPath, owned: ownedByNumber[e.episodeNumber])
            }
        } else {
            // No TMDB → show the downloaded episodes only.
            seasonEpisodes = owned.sorted { $0.number < $1.number }.map {
                PlayerEpisode(season: $0.season, number: $0.number, name: nil, stillPath: nil, owned: $0)
            }
        }
    }

    /// Switch playback to a chosen episode of the season, in-place (records the current episode's
    /// progress first). No-op if it's already the one playing. Resumes from the episode's saved
    /// position when partially watched (the resume provider decides); otherwise from the start.
    public func play(_ ep: Episode) {
        guard ep.season != episode?.season || ep.number != episode?.number else { return }
        Task { await self.recordCurrentProgress() }
        switchTo(ep, resumeAt: nil)
    }

    // MARK: - Init

    public init(request: PlaybackRequest,
         engine: VideoPlayerEngine,
         unrestrict: @escaping (String) async throws -> URL,
         recordProgress: @escaping (_ contentKey: String, _ sourceKey: String, _ position: Double, _ duration: Double) async -> Void,
         subtitles: SubtitleProvider?,
         details: MediaDetailsProviding? = nil,
         trackPreferences: TrackPreferenceStoring? = nil,
         resolveResume: ((String) async -> Double?)? = nil,
         prefetchLink: ((String) -> Void)? = nil,
         autoHideDelay: Double = 4,
         seekCoalesceWindow: Double = 0.35) {
        self.autoHideDelay = autoHideDelay
        self.seekCoalesceWindow = seekCoalesceWindow
        self.details = details
        self.trackPreferences = trackPreferences
        self.resolveResume = resolveResume
        self.prefetchLink = prefetchLink
        self.fromStart = request.fromStart
        self.item = request.item
        // Preferred source first, then remaining sources in quality order (deduped).
        self.sources = [request.source] + request.item.sources.bestFirst().filter { $0 != request.source }
        self.resumeAt = request.resumeAt
        self.label = request.label
        self.episode = request.episode
        self.contentKey = request.contentKey
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
        // The request's resumeAt is only the FALLBACK — loadCurrentSource() re-resolves the
        // saved position from the store (when a provider is wired) so resume can't race the
        // screen's watch-state load or go stale after a previous playback.
        resumeTarget = fromStart ? 0 : max(resumeAt ?? 0, 0)
        resumeSeekIssued = false
        pendingSeek = nil
        cancelCoalescedSeek()
        trackPrefsApplied = false
        lastSavedPosition = -.infinity
        loadTask?.cancel()
        loadTask = Task { await self.loadCurrentSource() }
    }

    private func loadCurrentSource() async {
        do {
            // The resume lookup first (a local store read, single-digit ms), then unrestrict —
            // which is instant anyway when the link was prefetched (PlayableLinkCache).
            if !fromStart, let resolveResume {
                let saved = await resolveResume(contentKey) ?? 0
                resumeTarget = saved > 0 ? saved : 0     // authoritative: overrides the UI hint
            }
            let url = try await unrestrict(currentSource.restrictedLink)
            guard !Task.isCancelled else { return }   // superseded by a newer reload()
            engine.load(url: url, headers: [:])
            engine.play()
            // Resume: a best-effort seek right at load — when VLC honors it while opening, the
            // stream starts AT the point (no pre-roll at 0, no double buffer). If it's dropped,
            // tick() issues the deferred seek exactly as before. Never a load-time start-time:
            // that clips the timeline so you can't rewind before the point.
            if resumeTarget > 0 { engine.seek(to: resumeTarget) }
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
        duration = t.duration

        // Resume: the load path already issued a best-effort seek. Arrival is checked FIRST so
        // that when VLC honored it (first ticks land at the point) no second seek fires; when it
        // was dropped (ticks start near 0) the deferred seek is issued ONCE here — a tick means
        // VLCKit has parsed the media and will now honor it. The loading overlay stays up until
        // the playhead actually reaches the point, so the bar never flashes 0 and jumps.
        if resumeTarget > 0 {
            if t.position >= resumeTarget - 5 {        // arrived (keyframe slack) → resume complete
                lastTickPosition = t.position
                resumeTarget = 0
            } else if !resumeSeekIssued {
                engine.seek(to: resumeTarget)
                resumeSeekIssued = true
            }
            return                                      // overlay stays; no promote/save while seeking
        }

        // Manual seek settling (bug #4): skip()/commitScrub() already moved `position` to the target
        // optimistically. VLCKit keeps echoing the PRE-seek time for a tick or two until the seek
        // lands; accepting those would snap the scrub bar back to the old spot. Hold the displayed
        // position at the target and drop ticks until one arrives that is decisively nearer the
        // target than the pre-seek origin (works for both forward and backward seeks, any distance).
        // `lastTickPosition` was set to the target when the seek was issued, so advance detection
        // below still fires on the landing tick.
        if let seek = pendingSeek {
            guard abs(t.position - seek.to) < abs(t.position - seek.from) else { return }
            pendingSeek = nil                           // landed → resume live tracking
        }

        position = t.position

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
            await recordProgress(contentKey, WatchKey.source(currentSource), position, duration)
        }
        maybeShowUpNext()
    }

    /// Reveal the "Up Next" bar once playback passes the content-end threshold (last subtitle cue,
    /// or a tail fallback) for a show with another episode — unless the viewer dismissed it.
    private func maybeShowUpNext() {
        guard hasNextEpisode, !upNextDismissed, !upNextVisible, phase == .playing,
              duration > 0, let threshold = upNextThreshold,
              position >= threshold, position < duration else { return }
        upNextVisible = true
        // Warm the next episode's unrestrict now (fire-and-forget) — by the time the countdown
        // auto-advances (or Play Now is tapped), the playable URL is already resolved.
        if let next = nextEpisode { prefetchLink?(next.source.restrictedLink) }
        upNextSecondsRemaining = upNextCountdownStart
        upNextTask?.cancel()
        upNextTask = Task { @MainActor in
            while upNextSecondsRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                upNextSecondsRemaining -= 1
            }
            playNext()                      // countdown elapsed → advance
        }
    }

    /// "Play Now" on the Up Next bar — advance immediately, skipping the countdown.
    public func playNextNow() {
        upNextTask?.cancel()
        playNext()
    }

    /// Dismiss the Up Next bar and stop it from re-appearing for this episode (the viewer wants to
    /// watch the credits). The file's real end then exits rather than auto-advancing.
    public func dismissUpNext() {
        upNextTask?.cancel()
        upNextVisible = false
        upNextDismissed = true
    }

    private func resetUpNext() {
        upNextTask?.cancel()
        upNextVisible = false
        upNextDismissed = false
        upNextSecondsRemaining = 0
        contentEndTime = nil
    }

    /// Pull the engine's current track lists into the published state. Called when playback starts
    /// and on every `.tracksChanged` event (VLCKit discovers elementary streams asynchronously, and
    /// an on-demand external subtitle appears after load).
    private func refreshTracks() {
        audioTracks = engine.audioTracks
        subtitleTracks = engine.subtitleTracks
        attachPendingSubtitleIfReady()
        applyTrackPreferencesIfNeeded()
    }

    /// Auto-apply the user's persisted audio/subtitle language once this source's tracks have been
    /// discovered (audio is always present, so its arrival means parsing is far enough along). Runs
    /// once per source (`reload()` re-arms it), so a later manual change isn't reverted by a
    /// subsequent `.tracksChanged`. A preferred he/en subtitle that isn't embedded auto-downloads —
    /// but only when its row is still `.idle`, so a daily-cap or in-flight download isn't re-hit
    /// every episode of a binge.
    private func applyTrackPreferencesIfNeeded() {
        guard let prefs = trackPreferences, !trackPrefsApplied, !audioTracks.isEmpty else { return }
        trackPrefsApplied = true

        if case .language(let lang) = prefs.preferredAudio,
           let match = audioTracks.first(where: { $0.language == lang }) {
            engine.selectAudioTrack(id: match.id)
            selectedAudioID = match.id
        }

        switch prefs.preferredSubtitle {
        case .automatic:
            break
        case .off:
            engine.selectSubtitleTrack(id: nil)
            selectedSubtitleID = nil
        case .language(let lang):
            if let match = subtitleTracks.first(where: { $0.language == lang }) {
                engine.selectSubtitleTrack(id: match.id)
                selectedSubtitleID = match.id
            } else if ["he", "en"].contains(lang),
                      subtitleRows.first(where: { $0.language == lang })?.state == .idle {
                Task { await self.requestSubtitle(language: lang) }
            }
        }
    }

    /// First frames are on screen. Clears the loading state so the overlay/spinner hide.
    private func markRendered() {
        hasRenderedFrame = true
        isBuffering = false
        isSwitching = false        // the new episode's media is on screen → end events are real again
    }

    private func finish() async {
        guard phase != .ended else { return }   // VLCKit can emit .stopped + .ended; finish once
        guard !isSwitching else { return }      // ignore the OLD media's late `.ended` mid-swap
        // Binge: a finished episode records its tail, then auto-advances to the next one in-place
        // (same player/engine) — unless the viewer dismissed the Up Next bar to watch the credits,
        // in which case the real file end exits. A movie or last episode records and dismisses.
        await recordCurrentProgress()
        if nextEpisode != nil, !upNextDismissed {
            advanceToNextEpisode()
            return
        }
        phase = .ended
        shouldDismiss = true
    }

    private func recordCurrentProgress() async {
        await recordProgress(contentKey, WatchKey.source(currentSource), position, duration)
    }

    /// Manually skip to the next episode (the transport "Next Episode" button). Records the current
    /// episode's position best-effort, then swaps in-place. No-op past the last episode.
    public func playNext() {
        guard hasNextEpisode else { return }
        Task { await self.recordCurrentProgress() }
        advanceToNextEpisode()
    }

    /// Swap the playing episode to the next in series order and reload from the start, in-place (no
    /// teardown/re-present, same engine + event loop). Subtitle state resets — externals are
    /// per-episode. Caller is responsible for recording the outgoing episode's progress.
    private func advanceToNextEpisode() {
        guard let next = nextEpisode else { return }
        switchTo(next, resumeAt: nil)
    }

    /// Swap the playing episode in-place (no teardown/re-present, same engine + event loop) and
    /// reload. Subtitle/track selection resets — externals are per-episode. Caller records the
    /// outgoing episode's progress.
    private func switchTo(_ ep: Episode, resumeAt newResume: Double?) {
        resetUpNext()                        // clear the bar/countdown + the old episode's content-end
        isSwitching = true                   // swallow the old media's late `.ended` until E2 renders
        episode = ep
        sources = [ep.source]
        sourceIndex = 0
        contentKey = WatchKey.content(forShow: item, episode: ep)
        label = "\(item.title) — S\(ep.season)·E\(ep.number)"
        resumeAt = newResume
        fromStart = false                    // the new episode resumes via the provider if mid-watched
        selectedAudioID = nil
        selectedSubtitleID = nil
        pendingSubtitleAttach = nil
        let initial: SubtitleRowState = subtitles == nil ? .noAccount : .idle
        subtitleRows = ["he", "en"].map { SubtitleRow(language: $0, state: initial) }
        reload()
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
        let origin = pendingSeek?.from ?? position   // a burst keeps the ORIGINAL pre-seek origin
        let target = clamp(position + delta)
        position = target            // optimistic: the scrub bar jumps to the new time immediately
        isBuffering = true           // …and shows the loading hint while the seek rebuffers
        lastTickPosition = target    // re-arm advance detection past the target
        pendingSeek = target != origin ? (from: origin, to: target) : nil   // hold the bar through stale ticks
        scheduleCoalescedSeek(to: target)
    }
    public func scrub(to seconds: Double) { engine.seek(to: clamp(seconds)) }

    /// See `seekCoalesceWindow`: leading seek fires immediately, skips landing inside the open
    /// window only retarget, and one trailing seek issues the final target when it closes.
    private func scheduleCoalescedSeek(to target: Double) {
        coalescedSeekTarget = target
        guard seekDispatchTask == nil else { return }   // window open → the trailing pass handles it
        engine.seek(to: target)
        dispatchedSeekTarget = target
        seekDispatchTask = Task { @MainActor in
            defer { seekDispatchTask = nil }
            try? await Task.sleep(for: .seconds(seekCoalesceWindow))
            guard !Task.isCancelled else { return }
            if let final = coalescedSeekTarget, final != dispatchedSeekTarget {
                engine.seek(to: final)
            }
            coalescedSeekTarget = nil
            dispatchedSeekTarget = nil
        }
    }

    /// Drop any open coalescing window (a direct seek — scrub commit / reload — supersedes it).
    private func cancelCoalescedSeek() {
        seekDispatchTask?.cancel()
        seekDispatchTask = nil
        coalescedSeekTarget = nil
        dispatchedSeekTarget = nil
    }

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
        let from = position
        position = scrubTarget
        lastTickPosition = scrubTarget
        isBuffering = true                     // loading hint while the seek rebuffers
        pendingSeek = scrubTarget != from ? (from: from, to: scrubTarget) : nil   // hold through stale ticks
        cancelCoalescedSeek()                  // a commit supersedes any open skip window
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

    public func selectSubtitle(id: String) {
        selectedSubtitleID = id
        engine.selectSubtitleTrack(id: id)
        recordPreferredSubtitle(forTrackID: id)
    }
    public func selectSubtitleOff() {
        selectedSubtitleID = nil
        engine.selectSubtitleTrack(id: nil)
        trackPreferences?.preferredSubtitle = .off
    }
    public func selectAudio(id: String) {
        selectedAudioID = id
        engine.selectAudioTrack(id: id)
        if let lang = audioTracks.first(where: { $0.id == id })?.language {
            trackPreferences?.preferredAudio = .language(lang)
        }
    }

    /// Persist a manually-selected subtitle by language. A downloaded sub's engine track often has a
    /// nil language, so resolve it from the owning language row first, then fall back to the track's
    /// own language tag (embedded subs).
    private func recordPreferredSubtitle(forTrackID id: String) {
        if let row = subtitleRows.first(where: { attachedTrackID($0) == id }) {
            trackPreferences?.preferredSubtitle = .language(row.language)
        } else if let lang = subtitleTracks.first(where: { $0.id == id })?.language {
            trackPreferences?.preferredSubtitle = .language(lang)
        }
    }

    // MARK: - Teardown

    public func teardown() async {
        eventTask?.cancel()
        loadTask?.cancel()
        hideControlsTask?.cancel()
        scrubBarHideTask?.cancel()
        upNextTask?.cancel()
        seekDispatchTask?.cancel()
        await recordCurrentProgress()
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
            // Requesting a language IS choosing it — make it sticky so the next episode/title
            // auto-downloads the same language without re-picking.
            trackPreferences?.preferredSubtitle = .language(language)
            // The downloaded cues tell us when the dialogue ends → drives "Up Next" at content-end
            // rather than the file end. Timestamps are ASCII, so isoLatin1 is a safe fallback decode
            // for non-UTF-8 (e.g. windows-1255 Hebrew) files.
            if let text = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .isoLatin1)) {
                contentEndTime = SubtitleTiming.lastCueEndSeconds(in: text)
            }
            // VLCKit attaches the slave asynchronously and signals via `.tracksChanged`; the new
            // track is usually NOT in the list yet. Remember the pending attach and finish it in
            // `refreshTracks()` once the track appears — that auto-selects it and turns the engine's
            // generic "Track N" into the language pill. Try once now in case it landed synchronously.
            let before = Set(engine.subtitleTracks.map(\.id))
            engine.addExternalSubtitle(url: url)
            pendingSubtitleAttach = (language, before)
            refreshTracks()
            scheduleSubtitleAttachTimeout(language: language)
        } catch let SubtitleError.dailyCapReached(reset) {
            setRow(language, .capReached(reset))
        } catch SubtitleError.notAuthenticated {
            setRow(language, .noAccount)
        } catch {
            setRow(language, .error)
        }
    }

    /// If a downloaded subtitle's slave track has appeared in the engine, select it, mark its
    /// language row `.attached`, and clear the pending attach. Idempotent — safe to call on every
    /// `.tracksChanged`. Marking the row attached also drops the engine's generic "Track N" pill:
    /// `embeddedSubtitleTracks` excludes any id a language row now owns.
    private func attachPendingSubtitleIfReady() {
        guard let pending = pendingSubtitleAttach,
              let newID = engine.subtitleTracks.first(where: { !pending.before.contains($0.id) })?.id
        else { return }
        engine.selectSubtitleTrack(id: newID)
        selectedSubtitleID = newID
        setRow(pending.language, .attached(newID))
        pendingSubtitleAttach = nil
    }

    /// Fallback if VLCKit never attaches the slave (e.g. an unreadable file): clear the pending
    /// download after a grace period so its row stops spinning and shows the retry-able error.
    private func scheduleSubtitleAttachTimeout(language: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, self.pendingSubtitleAttach?.language == language else { return }
            self.pendingSubtitleAttach = nil
            self.setRow(language, .error)
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
