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

    public internal(set) var phase: Phase = .preparing
    public internal(set) var position: Double = 0
    public internal(set) var duration: Double = 0
    public internal(set) var controlsVisible: Bool = true
    public internal(set) var audioTracks: [MediaTrack] = []
    public internal(set) var subtitleTracks: [MediaTrack] = []
    public internal(set) var subtitleRows: [SubtitleRow]
    public internal(set) var shouldDismiss: Bool = false

    /// "Up Next" bar state (shows near content-end for a show with another episode).
    public internal(set) var upNextVisible: Bool = false
    public internal(set) var upNextSecondsRemaining: Int = 0

    /// Currently-selected track ids — drives the settings sheet's selection indicator.
    public internal(set) var selectedAudioID: String?
    public internal(set) var selectedSubtitleID: String?   // nil = Off

    /// Transient feedback for the on-screen skip indicator. `seconds` is the SIGNED accumulated jump
    /// of the current skip burst (e.g. −20, +30 — repeated taps within a burst grow it); `id` bumps
    /// each skip so the view re-triggers its pop animation. Auto-clears ~0.8s after the last skip.
    public internal(set) var skipFeedback: SkipFeedback?
    public struct SkipFeedback: Equatable, Sendable {
        public let seconds: Double      // signed: negative = rewind, positive = forward
        public var id: Int              // monotonically bumped so equal amounts still re-animate

        /// "45s" under a minute; "1:10", "2:00" at or above it — the accumulated jump's magnitude.
        public var label: String {
            let s = Int(abs(seconds).rounded())
            return s < 60 ? "\(s)s" : String(format: "%d:%02d", s / 60, s % 60)
        }
    }
    var skipFeedbackClearTask: Task<Void, Never>?
    /// Hold-to-scan repeat loop (see `beginScan`).
    var scanTask: Task<Void, Never>?

    /// Output volume as a percentage (100 = unity, up to 200 = VLC-style boost). Re-applied on every
    /// track refresh so a boost survives episode swaps and VLCKit's async audio-object creation.
    public internal(set) var volumePercent: Int = 100

    /// A finished subtitle download waiting for VLCKit to actually attach the slave track — it
    /// appears asynchronously via `.tracksChanged`, not synchronously after `addExternalSubtitle`.
    /// `before` is the text-track id set captured just before the attach, so the freshly-appeared
    /// id is the one not in it. Resolved in `refreshTracks()`.
    var pendingSubtitleAttach: (language: String, before: Set<String>)?

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
    public internal(set) var isScrubbing: Bool = false
    public internal(set) var scrubTarget: Double = 0
    /// Whether the (UIKit-focusable) scrub surface holds focus — drives the bar's focused look.
    public private(set) var scrubberFocused: Bool = false
    /// Whether the thin scrub bar should be on screen (sticky for `scrubBarDwell` seconds after the
    /// last interaction). Distinct from `isScrubbing` (mid-gesture only).
    public internal(set) var scrubBarVisible: Bool = false

    /// First real video frame has rendered for the current source (sustained time advance or a real
    /// `.playing`). Gates the full-screen loading overlay so it never hides over a still-black
    /// picture.
    public internal(set) var hasRenderedFrame: Bool = false
    /// True only for a COLD open — the first load of a player session, when the screen is still
    /// black and a full-screen overlay is the right thing. An episode auto-advance reloads too
    /// (clearing `hasRenderedFrame`), but the viewer is already watching, so it must show the
    /// bar's inline spinner instead of taking the screen over.
    public var isColdOpen: Bool { !hasRenderedFrame && !isSwitching }
    /// Waiting on frames — initial load, a skip/seek, or a mid-stream rebuffer. Drives the loading
    /// indicator (full overlay before the first frame; a small inline hint after).
    public internal(set) var isBuffering: Bool = true

    // MARK: - Stored properties

    let item: MediaItem
    var sources: [MediaSource]
    var sourceIndex: Int = 0
    var resumeAt: Double?
    public internal(set) var label: String
    /// The episode currently playing (shows only) and the WatchKey it records progress under.
    /// Both change when we advance to the next episode in-place.
    var episode: Episode?
    var contentKey: String
    let engine: VideoPlayerEngine
    let unrestrict: (String) async throws -> URL
    /// Authoritative resume lookup (contentKey → saved seconds, nil/0 = start). Resolved at LOAD
    /// time so playback always resumes from the store's truth — the screen's watch state can be
    /// not-yet-loaded (tap Play right after Detail opens) or stale (immediate re-play) when the
    /// request was built. Also what lets retry/try-another-version resume where playback failed.
    let resolveResume: ((String) async -> Double?)?
    /// Resume lookup for backends that store progress as a FRACTION of the runtime (Trakt stores a
    /// percentage, not seconds). Resolved at load time, but converted to a seek target only once the
    /// media reports its duration — at load `duration` is still 0, so seconds aren't computable yet.
    /// Takes precedence over `resolveResume` when both are wired.
    let resolveResumeFraction: ((String) async -> Double?)?
    /// Scrobble lifecycle hooks (fraction 0…1 of the runtime). Optional: nil keeps the pre-Trakt
    /// behavior exactly, which is what every existing caller and unit test relies on.
    let onScrobbleStart: ((Double) async -> Void)?
    let onScrobblePause: ((Double) async -> Void)?
    let onScrobbleStop: ((Double) async -> Void)?
    /// Fire-and-forget unrestrict warm-up (PlayableLinkCache.prefetch) — called for the next
    /// episode's link when the Up Next bar appears, so a binge auto-advance starts instantly.
    let prefetchLink: ((String) -> Void)?
    /// "Start over" was explicitly chosen for the initial request — never resume it. Cleared on
    /// an episode switch (the provider decides for the new episode).
    var fromStart: Bool
    /// Records progress for the *currently playing* content — PlayerModel passes the live
    /// contentKey + sourceKey so next-episode advances record under the right keys.
    let recordProgress: (_ contentKey: String, _ sourceKey: String, _ position: Double, _ duration: Double) async -> Void
    let subtitles: SubtitleProvider?
    /// The system Now Playing surface (iPhone Remote app, Control Center, Siri, CEC). Optional —
    /// nil keeps the pre-Now-Playing behavior exactly, which every existing unit test relies on.
    let nowPlaying: NowPlayingControlling?
    /// On-demand TMDB episode metadata (names + stills) for the in-player episode strip. Optional —
    /// when nil (or for a movie) the strip simply carries no names/thumbnails.
    let details: MediaDetailsProviding?
    /// App-global preferred audio/subtitle language. Recorded on a manual pick and auto-applied once
    /// per loaded source. Optional — nil disables persistence (no preference recorded or applied).
    let trackPreferences: TrackPreferenceStoring?
    /// Whether the preferred tracks have been auto-applied for the current source (reset on reload),
    /// so a later manual change isn't reverted by subsequent `.tracksChanged` events.
    var trackPrefsApplied = false

    var eventTask: Task<Void, Never>?
    var loadTask: Task<Void, Never>?
    var hideControlsTask: Task<Void, Never>?
    var scrubBarHideTask: Task<Void, Never>?
    var lastSavedPosition: Double = -.infinity
    /// Last engine-reported position — to detect *sustained* advance (real frames) vs a single
    /// echoed seek tick.
    var lastTickPosition: Double = 0
    /// Resume: where to seek to once playback starts (0 = none) and whether that seek has fired. A
    /// deferred seek (not a load-time start-time) keeps the whole timeline seekable.
    var resumeTarget: Double = 0
    var resumeSeekIssued: Bool = false
    /// Ticks seen since the deferred resume seek was issued. `:input-fast-seek` lands on the
    /// nearest keyframe, which can be well outside the 5s arrival slack — arrival then never
    /// registers, the resume branch returns on every tick, and the path to `markRendered()` stays
    /// shut forever. After this many ticks we accept the playhead wherever it actually is.
    var resumeTicksSinceSeek = 0
    let resumeArrivalGraceTicks = 12
    /// A pending fractional resume (0…1) awaiting a known duration — converted to `resumeTarget`
    /// on the first tick that reports one, then cleared.
    var resumeFraction: Double = 0
    /// A manual seek (skip/commitScrub) in flight: `to` is the optimistic target the bar already
    /// shows, `from` the pre-seek playhead. While set, `tick()` ignores VLCKit's stale pre-seek
    /// time echoes (which would snap the bar back) until a tick arrives nearer `to` than `from`.
    var pendingSeek: (from: Double, to: Double)?
    /// True from the moment we swap episodes until the new media renders its first frame. The OLD
    /// media can emit a late `.ended` during that window; this flag makes `finish()` swallow it so a
    /// stale end can't auto-advance/exit a second time (the "it keeps jumping/restarting" bug).
    var isSwitching = false
    /// Persist the resume point every second of playback so Continue Watching / cross-device resume
    /// is never more than ~1s stale (SwiftData writes are cheap and CloudKit coalesces the sync).
    let saveInterval: Double = 1
    let autoHideDelay: Double
    let scrubBarDwell: Double = 5      // bar stays visible for 5s after the last interaction
    /// How long a load may sit without producing a first frame before it is called a failure.
    /// There was previously NO timeout anywhere in the load path, so a stalled open showed the
    /// overlay forever with no Retry.
    let loadTimeout: Double
    var loadWatchdog: Task<Void, Never>?

    /// Engine-seek coalescing for skip bursts: the first skip seeks immediately (instant
    /// response); further skips inside the window only move the target and ONE trailing seek
    /// fires at the final target — four fast double-taps become two engine seeks, not four
    /// full seek+rebuffer cycles.
    let seekCoalesceWindow: Double
    var seekDispatchTask: Task<Void, Never>?
    var coalescedSeekTarget: Double?
    var dispatchedSeekTarget: Double?
    /// Bumped for every coalescing window opened or cancelled. A window task only clears
    /// `seekDispatchTask` when its own generation is still current — a cancelled task's cleanup
    /// runs at its next suspension point, by which time a LIVE successor may already own the slot.
    /// Nulling it there made the next skip open a fresh window and seek eagerly instead of
    /// coalescing, which is the burst-rebuffering the coalescer exists to prevent.
    var seekGeneration: UInt64 = 0

    // MARK: - Up Next (binge)
    /// Last subtitle cue (seconds), when a sub was downloaded. A FLOOR for the Up Next bar — it
    /// won't fire while a line is still being spoken — but no longer triggers it directly (the last
    /// line is often well before the credits). nil → use the credits-lead estimate alone.
    var contentEndTime: Double?
    var upNextDismissed = false
    var upNextTask: Task<Void, Never>?
    let upNextCountdownStart = 10
    /// The credits are roughly the last ~30s of the file. The countdown should roll DURING the
    /// credits, so the bar appears no earlier than this before the end — never at the last spoken
    /// line (which is often well before the credits) nor during dialogue that runs late.
    private let upNextCreditsLead: Double = 30

    /// When the "Up Next" bar should appear (nil → never, e.g. no next episode or a too-short file).
    /// The LATER of the last subtitle cue and a credits-length before the end — so it lands in the
    /// credits, not the final scene — clamped so the 10s countdown still finishes before the file end.
    var upNextThreshold: Double? {
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
    public internal(set) var seasonEpisodes: [PlayerEpisode] = []

    // MARK: - Init

    public init(request: PlaybackRequest,
         engine: VideoPlayerEngine,
         unrestrict: @escaping (String) async throws -> URL,
         recordProgress: @escaping (_ contentKey: String, _ sourceKey: String, _ position: Double, _ duration: Double) async -> Void,
         subtitles: SubtitleProvider?,
         details: MediaDetailsProviding? = nil,
         trackPreferences: TrackPreferenceStoring? = nil,
         resolveResume: ((String) async -> Double?)? = nil,
         resolveResumeFraction: ((String) async -> Double?)? = nil,
         onScrobbleStart: ((Double) async -> Void)? = nil,
         onScrobblePause: ((Double) async -> Void)? = nil,
         onScrobbleStop: ((Double) async -> Void)? = nil,
         prefetchLink: ((String) -> Void)? = nil,
         nowPlaying: NowPlayingControlling? = nil,
         autoHideDelay: Double = 4,
         loadTimeout: Double = 30,
         seekCoalesceWindow: Double = 0.35) {
        self.autoHideDelay = autoHideDelay
        self.loadTimeout = loadTimeout
        self.seekCoalesceWindow = seekCoalesceWindow
        self.details = details
        self.trackPreferences = trackPreferences
        self.resolveResume = resolveResume
        self.resolveResumeFraction = resolveResumeFraction
        self.onScrobbleStart = onScrobbleStart
        self.onScrobblePause = onScrobblePause
        self.onScrobbleStop = onScrobbleStop
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
        self.nowPlaying = nowPlaying
        let initial: SubtitleRowState = subtitles == nil ? .noAccount : .idle
        self.subtitleRows = ["he", "en"].map { SubtitleRow(language: $0, state: initial) }
    }

    // MARK: - Lifecycle

    /// Progress through the current media as a 0…1 fraction (0 when the length isn't known yet).
    var currentFraction: Double {
        duration > 0 ? max(0, min(1, position / duration)) : 0
    }

    /// Manually skip to the next episode (the transport "Next Episode" button). Records the current
    /// episode's position best-effort, then swaps in-place. No-op past the last episode.
    public func playNext() {
        guard hasNextEpisode else { return }
        Task { await self.recordCurrentProgress() }
        advanceToNextEpisode()
    }

    // MARK: - Transport controls

    /// Resume. Distinct from `togglePlayPause` because the system Now Playing surface sends
    /// DISCRETE play and pause commands — a toggle does the wrong thing whenever that surface's
    /// idea of the state disagrees with ours.
    public func play() {
        guard phase != .playing else { return }
        engine.play()
        revealScrubBar()
    }

    /// Pause. See `play()` for why this is not a toggle.
    public func pause() {
        guard phase == .playing else { return }
        engine.pause()
        revealScrubBar()
    }

    /// Declare our transport to the system. This is what makes the iPhone Remote app render its
    /// +/-10s buttons and scrubber; it also enables Siri, Control Center and CEC TV remotes.
    func activateNowPlaying() {
        guard let nowPlaying else { return }
        nowPlaying.activate(NowPlayingHandlers(
            play: { [weak self] in self?.play() },
            pause: { [weak self] in self?.pause() },
            togglePlayPause: { [weak self] in self?.togglePlayPause() },
            skip: { [weak self] delta in self?.skip(delta) },
            seek: { [weak self] target in self?.scrub(to: target) },
            setRate: { [weak self] rate in self?.setPlaybackSpeed(rate) },
            nextTrack: hasNextEpisode ? { [weak self] in self?.playNextNow() } : nil
        ))
    }

    /// Push the current metadata + playhead to the system surface.
    func pushNowPlaying() {
        guard let nowPlaying else { return }
        nowPlaying.update(NowPlayingInfo(
            title: label,
            showName: episode != nil ? item.title : nil,
            duration: duration,
            position: position,
            rate: phase == .playing ? playbackSpeed : 0,
            artworkURL: TMDBClient.imageURL(path: item.posterPath, size: "w500")
        ))
    }

    /// Playback rate multiplier (1 = normal). Settings panel uses 0.5/0.75/1/1.25/1.5.
    public private(set) var playbackSpeed: Double = 1
    public func setPlaybackSpeed(_ rate: Double) {
        playbackSpeed = rate
        engine.setRate(rate)
    }

    // MARK: - Controls auto-hide

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

    // MARK: - Subtitle browser

    public enum SubtitleSearchState: Equatable {
        case idle, searching, loaded, failed
    }

    /// Subtitle tracks muxed into the media.
    public var embeddedTracks: [MediaTrack] { subtitleTracks.filter { !$0.isExternal } }
    /// Subtitle tracks attached from a downloaded file this session.
    public var downloadedTracks: [MediaTrack] { subtitleTracks.filter(\.isExternal) }

    public internal(set) var subtitleSearchState: SubtitleSearchState = .idle
    public internal(set) var subtitleSearchResults: [SubtitleMatch.Ranked] = []
    /// The language whose results are currently shown.
    public internal(set) var subtitleSearchLanguage: String?
    /// The moviehash of the playing file, resolved lazily on the first browser search and reused.
    var currentMoviehash: String?
    var moviehashResolved = false

    // MARK: - Test hook

    /// Yields the current task so in-flight async work can complete before assertions.
    /// Used only in unit tests — see `PlayerModelTests`.
    public func waitForIdleForTesting() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    /// Test seam: perform a full scrub cycle to `seconds` in one call.
    func commitScrubForTesting(to seconds: Double) {
        beginScrub()
        updateScrub(by: seconds - scrubTarget)
        commitScrub()
    }
}
