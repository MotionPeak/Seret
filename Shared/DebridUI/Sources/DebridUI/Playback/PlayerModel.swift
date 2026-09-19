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

        /// `.failed` is terminal: it is showing Retry / Try another version, and only an explicit
        /// viewer action may leave it. Engine events that arrive afterwards must not overwrite it.
        public var isFailed: Bool { if case .failed = self { return true }; return false }
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

    /// Why a subtitle chosen in the search browser did not end up on screen.
    ///
    /// The language rows have carried their own reasons for a long time — the panel prints
    /// "Hebrew — daily limit reached" and "Hebrew — add an OpenSubtitles account". The browser had
    /// nothing: every cause collapsed into `subtitleSearchState = .failed`, and both platforms
    /// closed the browser the instant the pick returned, so a missing account, an exhausted quota
    /// and a dead network were indistinguishable from the press having been ignored. On the Apple
    /// TV that is what the viewer saw, every time.
    public enum SubtitlePickFailure: Equatable, Sendable {
        case noAccount
        case capReached(Date?)
        case failed

        public var message: String {
            switch self {
            case .noAccount:
                "Add an OpenSubtitles account in Settings to download subtitles."
            case .capReached(let reset):
                Self.capMessage(reset)
            case .failed:
                "That subtitle couldn't be downloaded. Try another one."
            }
        }

        private static func capMessage(_ reset: Date?) -> String {
            let base = "The OpenSubtitles daily download limit is used up."
            guard let reset else { return "\(base) Try again tomorrow." }
            let when = reset.formatted(date: .omitted, time: .shortened)
            return "\(base) It resets at \(when)."
        }
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
    /// A hold-to-scan is travelling right now. Published because every OTHER input has to be able to
    /// call it off — a play/pause press, a click, Menu. Without that, the only things that could stop
    /// a scan were releasing the arrow, an overlay taking the remote, and the loop's own timeout, so
    /// a lost release left the viewer watching the film race away with no way to intervene.
    public internal(set) var isScanning: Bool = false
    /// Bumped whenever a scan starts or ends, so a self-terminating scan can tell whether it is
    /// still the live one before tidying up — same guard as `seekGeneration`.
    var scanGeneration: UInt64 = 0
    /// Hold-to-scan shape: the first jump, how fast it grows per repeat, and the ceiling on one
    /// jump. The ceiling is what keeps a long hold controllable.
    static let scanFirstStep: Double = 10
    static let scanGrowth: Double = 1.5
    static let scanMaxStep: Double = 30
    /// Seconds between repeats of a held scan, and the longest one hold may run before it stops
    /// itself. Injectable so tests don't have to wait real seconds.
    let scanInterval: Double
    let scanMaxDuration: Double
    /// How often a held scan is allowed to actually seek the ENGINE. Repeats are far quicker than
    /// this: the rest of them move the displayed playhead only. A network seek costs libvlc a full
    /// pipeline re-fill (2s of pre-roll on tvOS) and blocks the main thread while the demuxer moves,
    /// so seeking on every repeat asked for a fill four times a second, never completed one, and
    /// starved the remote of input for the length of the hold. See `scanSeekStride`.
    let scanSeekInterval: Double
    /// Repeats per engine seek — at least one, so a scan always seeks at the very first repeat.
    var scanSeekStride: Int { max(1, Int((scanSeekInterval / max(scanInterval, 0.001)).rounded())) }

    /// Output volume as a percentage (100 = unity, up to 200 = VLC-style boost). Re-applied on every
    /// track refresh so a boost survives episode swaps and VLCKit's async audio-object creation.
    public internal(set) var volumePercent: Int = 100

    /// A finished subtitle download waiting for VLCKit to actually attach the slave track — it
    /// appears asynchronously via `.tracksChanged`, not synchronously after `addExternalSubtitle`.
    /// `before` is the text-track id set captured just before the attach, so the freshly-appeared
    /// id is the one not in it. Resolved in `refreshTracks()`.
    var pendingSubtitleAttach: (language: String, url: URL, before: Set<String>)?

    /// Where each subtitle FILE attached this session ended up, by the URL it was attached from.
    ///
    /// libvlc keys a playback slave by URL: handing it one it already holds surfaces no new track
    /// at all. The attach handshake waits for a newcomer, so a second ask for the same file waited
    /// for something that could never arrive and timed out into "not found, try Search" — with a
    /// perfectly good track sitting in the list, deselected. Remembering where each file landed
    /// turns that second ask into what the viewer meant by it: select the track again.
    /// Cleared with the rest of the per-file subtitle state on a source change.
    var attachedSubtitleTracks: [URL: String] = [:]

    /// Cue lists for downloaded subtitles, keyed by the file that was attached to the engine.
    ///
    /// Parsed on the way in, where the text has already been decoded for the rate check — so asking
    /// whether a hand sync is possible costs nothing, the panel opens without reading a file, and
    /// switching between two downloaded tracks shows the right lines for each.
    var subtitleCues: [URL: [SubtitleCue]] = [:]

    /// The hand sync in progress, or nil when the panel is closed. (Stored here rather than in
    /// `PlayerModel+ManualSync.swift` because Swift does not allow stored properties in extensions.)
    var manualSync: ManualSyncSession?

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

    /// The language a downloaded subtitle was fetched FOR, named for a picker row.
    ///
    /// VLCKit calls a slave track "Track 3" and reports no language for it, so the pickers had
    /// nothing to print but that — the viewer asked for Hebrew and got a row called "Track 3",
    /// which reads as the app having done something else entirely. The language row that owns the
    /// track is the only thing that knows.
    public func downloadedLanguageName(forTrackID id: String) -> String? {
        subtitleRows.first { attachedTrackID($0) == id }.map { Self.languageName($0.language) }
    }

    /// "he" → "Hebrew". Falls back to the code in capitals for anything the system cannot name.
    ///
    /// Named in English, not `Locale.current`: every other word in these panels is English, and the
    /// one-tap pills above this row say "Hebrew" in as many words. On a Hebrew-locale device a
    /// current-locale name would put "עברית" directly beneath "Hebrew" and read as two different
    /// things.
    public static func languageName(_ code: String) -> String {
        // Some containers write a full name where a code belongs ("English", "Brazilian
        // Portuguese"). Resolving that yields nothing, and the fallback would SHOUT it.
        guard code.count <= 3 else { return code.capitalized }
        return Self.englishNames.localizedString(forLanguageCode: code)?.capitalized
            ?? code.uppercased()
    }

    private static let englishNames = Locale(identifier: "en_US")

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
    /// The watch key of the file playing. Public because a view whose contents belong to ONE file —
    /// the subtitle browser — keys its work on it, so a swap re-runs rather than stranding it.
    public internal(set) var contentKey: String
    let engine: VideoPlayerEngine
    let unrestrict: (String) async throws -> URL
    /// Authoritative resume lookup (contentKey → saved seconds, nil/0 = start). Resolved at LOAD
    /// time so playback always resumes from the store's truth — the screen's watch state can be
    /// not-yet-loaded (tap Play right after Detail opens) or stale (immediate re-play) when the
    /// request was built. Also what lets retry/try-another-version resume where playback failed.
    let resolveResume: ((String) async -> Double?)?
    /// Fire-and-forget unrestrict warm-up (PlayableLinkCache.prefetch) — called for the next
    /// episode's link when the Up Next bar appears, so a binge auto-advance starts instantly.
    let prefetchLink: ((String) -> Void)?
    /// "Start over" was explicitly chosen for the initial request — never resume it. Cleared on
    /// an episode switch (the provider decides for the new episode).
    var fromStart: Bool
    /// Records progress for the *currently playing* content — PlayerModel passes the live
    /// contentKey + sourceKey so next-episode advances record under the right keys.
    ///
    /// `finished` is the player's own answer, because only it knows where the dialogue ends. The
    /// store keeps a runtime-fraction fallback for callers with no player, and whichever says
    /// "watched" first wins.
    let recordProgress: (_ contentKey: String, _ sourceKey: String, _ position: Double, _ duration: Double, _ finished: Bool) async -> Void
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
    /// The viewer picked a subtitle by hand — the automatic choice stops re-deciding, exactly as
    /// `audioPickedByUser` does for audio.
    var subtitlePickedByUser = false
    /// The subtitle track ids the automatic choice was last computed from. The preference used to
    /// be applied ONCE, gated on AUDIO tracks being present — but VLCKit discovers elementary
    /// streams one at a time, so the subtitle set was routinely still empty at that moment. The
    /// embedded track that arrived a beat later was never matched and the latch never reopened,
    /// which is why a chosen subtitle language had to be re-picked on nearly every play.
    var subtitleSelectionSignature: [String] = []
    /// The on-demand download fallback has been used for this source. Kept strictly one-shot: the
    /// OpenSubtitles account is daily-capped, so a binge must not spend a download per episode.
    var subtitleFallbackRequested = false
    /// An `.off` preference has been pushed to the engine for this source at least once.
    var subtitleOffAsserted = false
    var subtitleFallbackTask: Task<Void, Never>?
    /// Measures the film's audio so a downloaded subtitle can be lined up against it. Optional —
    /// nil simply means the auto-sync action is not offered.
    let audioProbe: AudioLoudnessProbing?
    /// How much of the film to listen to, and how far out a subtitle may be. Injectable because a
    /// realistic window is a few thousand frames searched over a few thousand shifts, and eight
    /// tests of that starve every timing-sensitive suite sharing the machine.
    let autoSyncWindow: Double
    let autoSyncMaxLag: Double
    let autoSyncMinimumHalf: Double
    /// Where an auto-sync measurement has got to. Drives the row's label and spinner.
    public internal(set) var autoSyncState: AutoSyncState = .idle
    /// How far the running measurement has got, for the bar over the picture. Nil when none runs.
    public internal(set) var autoSyncProgress: AutoSyncProgress?
    /// What the bar says once the measurement ends — the actual outcome, offset included. Held for
    /// a few seconds and then cleared: a permanent banner over the picture is a worse outcome than
    /// no banner, and the settings panel still reports the state for as long as anyone cares.
    public internal(set) var autoSyncOutcome: String?
    var autoSyncOutcomeTask: Task<Void, Never>?
    /// How long the outcome stays on screen — long enough to read a sentence at ten feet. Per
    /// instance rather than a static, so a test can shorten it without touching every other model.
    var autoSyncOutcomeSeconds: Double = 6
    /// Owned by the model, not by the view that started it: a sync takes minutes and has to survive
    /// the settings panel closing, while still dying with the player.
    var autoSyncTask: Task<Void, Never>?
    var autoSyncProgressTask: Task<Void, Never>?
    var autoSyncETA = ETAEstimator()

    /// How long to let VLCKit finish discovering subtitle tracks before falling back to a download.
    /// There is no "discovery finished" event, so this is the only thing separating "this file has
    /// no subtitles" from "they haven't been parsed yet". Injectable so tests don't sleep.
    let subtitleFallbackDelay: Double
    /// The viewer picked an audio track by hand — the automatic choice stops re-deciding.
    var audioPickedByUser = false
    /// The audio track ids the automatic choice was last computed from, so it re-runs only when
    /// VLCKit actually discovers a different set (see `applyAudioPreference`).
    var audioSelectionSignature: [String] = []

    #if DEBUG
    /// Time events seen this session. `pendingSeekGraceTicks` is denominated in ticks, so how long
    /// that window actually IS depends entirely on how often VLCKit reports time — which is a
    /// libvlc implementation detail, not something the app sets. Counting them is the only way to
    /// know whether the window is generous or nearly zero.
    var debugTickCount = 0
    /// DEBUG resume-probe epoch (see PlayerModel+SeekProbe).
    var resumeProbeStart: Double = 0
    /// The `-autoSeek` probe has fired for this session (see `PlayerModel+SeekProbe`).
    var seekProbeStarted = false
    /// The `-autoSubtitle` probe has fired for this session (see `PlayerModel+SubtitleProbe`).
    var subtitleProbeStarted = false
    #endif
    /// `start()` has run. See `start()` — the screen's `.onAppear` can fire more than once.
    var hasStarted = false
    /// `finish()` is past its guards. Closed synchronously, because VLCKit reports the end of a file
    /// twice (`.stopping` then `.stopped`) and both reach `finish()` before its first `await`.
    var isFinishing = false
    /// A progress write is in flight. The write is fire-and-forget so it cannot stall the event
    /// loop, and this keeps exactly one of them running so they can't reorder or pile up.
    var isSavingProgress = false
    /// The progress write in flight. Fire-and-forget by design — awaiting it inside the event loop
    /// is what used to freeze the scrub bar for the length of the write — so this handle exists
    /// only so the test seam can tell whether it has landed, and nothing cancels it.
    var progressSaveTask: Task<Void, Never>?
    /// Fallback timer for a subtitle download VLCKit never attaches. Held so it can be cancelled —
    /// an orphan from a previous episode used to fire against the CURRENT one's pending attach.
    var subtitleAttachTimeoutTask: Task<Void, Never>?
    var eventTask: Task<Void, Never>?
    var loadTask: Task<Void, Never>?
    /// The `.ended` handler, which `handle(state:)` spawns rather than awaits. Held so the test
    /// seam can wait for it — the end of a file is decided inside it, several awaits deep.
    /// Never cancelled here: VLCKit reports the end twice and `finish()`'s own latch is what makes
    /// the second one a no-op, so a second `.ended` must be allowed to run and hit that latch.
    var finishTask: Task<Void, Never>?
    /// How many engine events the event loop has finished handling.
    ///
    /// This is the signal `waitForIdleForTesting` waits on. It used to sleep 20ms and hope, which
    /// is not a wait at all: on a loaded machine the assertion ran before the work and five tests
    /// failed at random across the package.
    var handledEventCount = 0
    /// The engine's stream has ended, so nothing further will ever be handled. `stop()` finishes
    /// it, and anything emitted afterwards is dropped — which the test seam has to know about, or
    /// it would wait for a count that can no longer move.
    var eventLoopFinished = false
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
    /// A manual seek (skip/commitScrub) in flight: `to` is the optimistic target the bar already
    /// shows, `from` the pre-seek playhead. While set, `tick()` ignores VLCKit's stale pre-seek
    /// time echoes (which would snap the bar back) until a tick arrives nearer `to` than `from`.
    var pendingSeek: (from: Double, to: Double)?
    /// Ticks seen since the manual seek was issued. libvlc can DROP a seek outright — an unseekable
    /// stretch, a stalled socket — and then no tick ever lands nearer the target, so the displayed
    /// playhead froze at a time the film never reached, the loading hint stuck, and progress stopped
    /// being written for the rest of the session. Same bounded-wait shape as `resumeTicksSinceSeek`.
    var pendingSeekTicks = 0
    let pendingSeekGraceTicks = 12
    /// True from the moment we swap episodes until the new media renders its first frame. The OLD
    /// media can emit a late `.ended` during that window; this flag makes `finish()` swallow it so a
    /// stale end can't auto-advance/exit a second time (the "it keeps jumping/restarting" bug).
    var isSwitching = false
    /// The engine is holding the media THIS load resolved. False from `reload()` until
    /// `loadCurrentSource()` has actually called `engine.load(...)`.
    ///
    /// That gap is not small: `reload()` returns immediately, but the load behind it awaits the
    /// resume lookup and then an RD unrestrict — seconds on a cold link. For all of it the engine
    /// is still playing the OUTGOING file and still emitting its `.time` events, and `tick()` had
    /// no way to tell those from the new episode's. It attributed the old file's near-end playhead
    /// to the incoming episode, and every consequence followed from that one mis-attribution:
    /// `maybeShowUpNext()` compared a stale position against a threshold built from the stale
    /// duration and re-armed the bar, whose countdown then advanced AGAIN (pick E1, land on E3);
    /// the progress write put ~99% of E1's runtime under E2's content key, marking an unwatched
    /// episode finished and destroying its resume point; and `markRendered()` disarmed the load
    /// watchdog guarding the incoming episode, so a dead link sat on the spinner with no Retry.
    var engineHoldsCurrentMedia = false
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

    /// Whether a playhead has passed the point this title counts as watched.
    ///
    /// Takes the position and runtime rather than reading `position`/`duration`, because the one
    /// caller that matters most reads them SYNCHRONOUSLY before handing the write to a Task — an
    /// episode swap replaces both underneath it otherwise, and the flag would describe the
    /// incoming episode rather than the one just finished.
    ///
    /// `contentEndTime` — the last subtitle cue — is what makes this better than any fraction: it
    /// is where the dialogue ends, which is where the film is over.
    func hasReachedEnd(at position: Double, duration: Double) -> Bool {
        WatchThreshold.hasReachedEnd(position: position, duration: duration,
                                     lastSubtitleCue: contentEndTime)
    }

    // MARK: - Computed helpers

    public var canTryAnotherVersion: Bool { sourceIndex + 1 < sources.count }
    public var currentSource: MediaSource { sources[sourceIndex] }

    /// The next episode in series order after the one playing, if any. `nil` for movies, for the
    /// last episode, or when the item carries no season data (e.g. an Add-flow play).
    public var nextEpisode: Episode? {
        guard let episode else { return nil }
        let ordered = orderedEpisodes
        guard let i = ordered.firstIndex(where: { $0.season == episode.season && $0.number == episode.number }),
              i + 1 < ordered.count else { return nil }
        return ordered[i + 1]
    }

    /// Every episode of the show in series order, sorted once.
    ///
    /// `item` is fixed for the life of the model, but this was re-sorted and re-flattened on every
    /// read — and it is read on every playback tick, through `maybeShowUpNext`, and again in each
    /// SwiftUI body that asks `hasNextEpisode`. For a long-running show that is its whole episode
    /// list, sorted several times a second, for an answer that cannot change.
    ///
    /// `@ObservationIgnored` because filling the cache is a write, and an observed write during a
    /// view update is exactly the "modifying state during view update" trap.
    @ObservationIgnored private var orderedEpisodesCache: [Episode]?

    private var orderedEpisodes: [Episode] {
        if let orderedEpisodesCache { return orderedEpisodesCache }
        let ordered = item.seasons
            .sorted { $0.number < $1.number }
            .flatMap { $0.episodes.sorted { $0.number < $1.number } }
        orderedEpisodesCache = ordered
        return ordered
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
         recordProgress: @escaping (_ contentKey: String, _ sourceKey: String, _ position: Double, _ duration: Double, _ finished: Bool) async -> Void,
         subtitles: SubtitleProvider?,
         details: MediaDetailsProviding? = nil,
         trackPreferences: TrackPreferenceStoring? = nil,
         resolveResume: ((String) async -> Double?)? = nil,
         prefetchLink: ((String) -> Void)? = nil,
         nowPlaying: NowPlayingControlling? = nil,
         autoHideDelay: Double = 4,
         loadTimeout: Double = 30,
         seekCoalesceWindow: Double = 0.35,
         scanInterval: Double = 0.5,
         scanSeekInterval: Double = 1.5,
         scanMaxDuration: Double = 15,
         subtitleFallbackDelay: Double = 2,
         audioProbe: AudioLoudnessProbing? = nil,
         autoSyncWindow: Double = 300,
         autoSyncMaxLag: Double = 120,
         autoSyncMinimumHalf: Double = SubtitleSync.minimumHalfSeconds) {
        self.subtitleFallbackDelay = subtitleFallbackDelay
        self.audioProbe = audioProbe
        self.autoSyncWindow = autoSyncWindow
        self.autoSyncMaxLag = autoSyncMaxLag
        self.autoSyncMinimumHalf = autoSyncMinimumHalf
        self.autoHideDelay = autoHideDelay
        self.loadTimeout = loadTimeout
        self.seekCoalesceWindow = seekCoalesceWindow
        self.scanInterval = scanInterval
        self.scanSeekInterval = scanSeekInterval
        self.scanMaxDuration = scanMaxDuration
        self.details = details
        self.trackPreferences = trackPreferences
        self.resolveResume = resolveResume
        self.prefetchLink = prefetchLink
        self.fromStart = request.fromStart
        self.item = request.item
        // Preferred source first, then remaining sources in quality order (deduped).
        // An EPISODE's copies live on the episode — `item.sources` is a movie's list and is empty
        // for a show, which is why an episode used to open with exactly one source and could never
        // fall back when a stream went bad.
        let owned = request.episode?.sources ?? request.item.sources
        self.sources = [request.source] + owned.bestFirst().filter { $0 != request.source }
        self.resumeAt = request.resumeAt
        self.label = request.label
        self.episode = request.episode
        self.contentKey = request.contentKey
        self.engine = engine
        self.unrestrict = unrestrict
        self.recordProgress = recordProgress
        self.subtitles = subtitles
        self.nowPlaying = nowPlaying
        self.subtitleRows = Self.freshSubtitleRows(hasAccount: subtitles != nil)
    }

    /// The one-tap language rows in their untouched state. One definition, because three places
    /// need it — construction, an episode swap, and every `reload()` — and a copy that drifted
    /// would leave a row claiming a track the new media does not have.
    static func freshSubtitleRows(hasAccount: Bool) -> [SubtitleRow] {
        let initial: SubtitleRowState = hasAccount ? .idle : .noAccount
        return ["he", "en"].map { SubtitleRow(language: $0, state: initial) }
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
        recordOutgoingProgress()
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
        pushNowPlaying()          // the system extrapolates the playhead from rate — tell it
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
    /// Why the last browser pick produced nothing, for the browser to print. Cleared by a pick that
    /// works and by starting a new search — a stale complaint must not outlive the attempt.
    public internal(set) var subtitlePickFailure: SubtitlePickFailure?
    /// Seconds the subtitle track is shifted by. Positive shows each line LATER. Session-scoped
    /// and reset for every new source — an offset dialled for one file means nothing for the next.
    public internal(set) var subtitleDelay: Double = 0
    /// Far more than any real correction needs, but a rate-mismatched subtitle an hour into a film
    /// can genuinely be minutes out, and clamping tighter than the problem helps nobody.
    static let maxSubtitleDelay: Double = 300

    /// The rate the SELECTED subtitle was authored at, when the viewer has said it differs from
    /// this file's. nil — the default — means no drift correction is running.
    ///
    /// This is what makes a MUXED track fixable. An external subtitle is rewritten before it is
    /// attached (`SubtitleRetimer`), but a track inside the container cannot be rewritten, and a
    /// constant offset cannot answer a rate error. A constant offset RECOMPUTED ON EVERY TICK can:
    /// the correction grows exactly as fast as the drift does.
    public internal(set) var subtitleSourceFPS: Double?

    /// What a 25fps subtitle is almost always played against, used when the engine will not report
    /// the file's rate. Assuming it is better than refusing to correct at all — every release this
    /// matters for is a 23.976 encode, and the viewer can see the result and switch it back off.
    static let assumedVideoFPS = 23.976

    /// Declare the selected subtitle's authored frame rate, or nil to stop correcting.
    public func setSubtitleSourceFPS(_ fps: Double?) {
        subtitleSourceFPS = fps
        applyEffectiveSubtitleDelay(force: true)
    }
    public var isCorrectingSubtitleDrift: Bool { subtitleSourceFPS != nil }

    /// Nudge the subtitle offset. Positive shows lines later, negative earlier.
    public func adjustSubtitleDelay(by delta: Double) { applySubtitleDelay(subtitleDelay + delta) }
    /// Back to the file's own timing.
    public func resetSubtitleDelay() { applySubtitleDelay(0) }

    func applySubtitleDelay(_ seconds: Double) {
        subtitleDelay = min(max(seconds, -Self.maxSubtitleDelay), Self.maxSubtitleDelay)
        applyEffectiveSubtitleDelay(force: true)
        rememberSubtitleDelay()
    }

    /// Keep the offset for this exact file and subtitle, so resuming tomorrow does not mean
    /// syncing again.
    ///
    /// Written for whatever lands in `subtitleDelay` — a press, a nudge, a chip, an auto-sync
    /// result — because they are all the same answer to the same question, and re-measuring audio
    /// on every resume is minutes the viewer should not spend twice.
    func rememberSubtitleDelay() {
        guard let prefs = trackPreferences, let file = selectedDownloadedSubtitleFile else { return }
        prefs.record(subtitleDelay: subtitleDelay,
                     forSource: WatchKey.source(currentSource),
                     subtitle: file.lastPathComponent)
    }

    /// Re-apply what was dialled for this file and this subtitle last time, if anything was.
    ///
    /// Narrower than the load-time reset on purpose: that clears the offset for every new source,
    /// and this puts one back only when the same subtitle is attached to the same file again.
    func restoreSubtitleDelay() {
        guard let prefs = trackPreferences, let file = selectedDownloadedSubtitleFile,
              let saved = prefs.subtitleDelay(forSource: WatchKey.source(currentSource),
                                              subtitle: file.lastPathComponent),
              saved != subtitleDelay else { return }
        applySubtitleDelay(saved)
    }

    /// When the current `position` was true. The sub-second part of `preciseNow` is reconstructed
    /// from how long ago that was.
    var positionStamp: ContinuousClock.Instant?

    /// Extrapolate no further than this. A tick arrives every second; if one has not for several,
    /// playback is stalled or the state is stale, and guessing further would invent a number.
    static let maxClockExtrapolation: Double = 1.5

    /// The playhead to timestamp a viewer's action against.
    ///
    /// `position` is whatever the last time notification said, and VLCKit posts that about once a
    /// second. Asking libvlc directly does NOT help: measured on a real stream, its own clock is
    /// quantised to the same one-second step — two presses 0.43s apart returned the identical
    /// 898.414. So the sub-second part cannot be read, only reconstructed: take the last figure the
    /// engine gave and add however long ago it arrived, scaled by the playback rate.
    ///
    /// `engine.preciseTime` is still preferred as the base when an engine offers it, because an
    /// engine with a genuinely fine clock (an AVPlayer fast-path, say) should not be thrown away —
    /// on such an engine the elapsed term is a fraction of a tick and costs nothing.
    ///
    /// Paused, the playhead is not moving, so the figure stands as it is.
    var preciseNow: Double {
        let base = engine.preciseTime ?? position
        guard phase == .playing, let stamp = positionStamp else { return base }
        let elapsed = Double(stamp.duration(to: .now).components.seconds)
            + Double(stamp.duration(to: .now).components.attoseconds) / 1e18
        return base + min(max(elapsed, 0), Self.maxClockExtrapolation) * playbackSpeed
    }

    /// The lines of the selected subtitle, when it is one we downloaded.
    public var manualSyncCues: [SubtitleCue] {
        selectedDownloadedSubtitleFile.flatMap { subtitleCues[$0] } ?? []
    }

    /// Whether a hand sync is possible at all: a downloaded subtitle whose lines we could read.
    ///
    /// A track muxed into the container never qualifies — we hold no cue list for it, so there is
    /// nothing for a press to be measured against. That is the same boundary auto-sync draws.
    public var canManualSync: Bool { !manualSyncCues.isEmpty }

    /// How far the running drift correction has grown by the current position.
    ///
    /// A cue sitting at file-time `s` must be shown at `s × f`, where `f` is the subtitle's rate
    /// over the video's. At playback time `t` the cue in question is the one at `t − d`, so
    /// `t = (t − d) × f` and the offset needed is `d = t × (1 − 1/f)`. For a 25fps subtitle on a
    /// 23.976 file that is 4.096% of elapsed time — 2m27s an hour in, which is exactly the drift.
    public var subtitleDriftDelay: Double {
        guard let factor = subtitleDriftFactor else { return 0 }
        return position * (1 - 1 / factor)
    }

    /// The subtitle's authored rate over the video's actual rate, or nil when no correction applies.
    var subtitleDriftFactor: Double? {
        guard let source = subtitleSourceFPS, source > 0 else { return nil }
        let video = (engine.videoFPS ?? Self.assumedVideoFPS)
        guard video > 0 else { return nil }
        let factor = source / video
        return abs(factor - 1) > 0.002 ? factor : nil
    }

    /// The hand-dialled offset plus however far the drift correction has grown. One place, because
    /// every caller must send the SUM — sending either alone silently discards the other.
    ///
    /// Rate-limited by value, not by time. The drift correction is recomputed every tick but only
    /// grows 40ms a second, and changing a subtitle offset makes libvlc resync the SPU stream —
    /// which can clear the line currently on screen. Poking it once a second for a change nobody
    /// can perceive would risk exactly the symptom this whole area is about. `force` is for the
    /// deliberate acts (a nudge, a reset, arming the correction, re-asserting after a track change),
    /// which must land whatever the last pushed value was.
    static let subtitleDelayEpsilon = 0.2

    func applyEffectiveSubtitleDelay(force: Bool = false) {
        let value = subtitleDelay + subtitleDriftDelay
        if !force, let pushed = pushedSubtitleDelay,
           abs(value - pushed) < Self.subtitleDelayEpsilon { return }
        pushedSubtitleDelay = value
        #if DEBUG
        subtitleProbe(String(format: "delay -> %+.3fs%@", value, force ? " (forced)" : ""))
        #endif
        engine.setSubtitleDelay(value)
    }

    /// The last value actually handed to the engine, so the tick can tell a meaningful change from
    /// the 40ms one it makes every second.
    var pushedSubtitleDelay: Double?

    #if DEBUG
    /// Last subtitle track set the probe printed, so it only reports actual churn.
    var lastProbedTrackSet: String?
    var tracksChangedCount = 0
    var tracksChangedWindowStart: TimeInterval = 0
    #endif

    /// How much the attached subtitle's timing was stretched to match this file's frame rate, or
    /// nil when it needed no correction. Surfaced so a viewer can see that a correction happened
    /// rather than wondering why the timings differ from the file they downloaded.
    public internal(set) var subtitleRetimeFactor: Double?
    /// The moviehash of the playing file, resolved lazily on the first browser search and reused.
    var currentMoviehash: String?
    var moviehashResolved = false

    // MARK: - Test hook

    /// Test seam: let the model's own tasks run a turn. Distinct from `waitForIdleForTesting` only
    /// in name — this one reads as "let what I just started take effect".
    ///
    /// Still a plain sleep, deliberately. Its callers are the auto-sync progress and manual-sync
    /// suites, which measure elapsed time and are `.serialized` for that reason: what they want
    /// from this is that real time passes, not that the model went quiet.
    func settleForTesting() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 30_000_000)
    }

    /// Wait until the work this model has in flight has actually landed.
    ///
    /// This waits on real signals — the load task's completion, and the event loop having HANDLED
    /// every event the engine has yielded — rather than on a duration. It used to be
    /// `Task.sleep(20ms)`, which is not a wait but a bet: the work usually finished inside the
    /// window, and when the machine was busy (the whole package's suites run in parallel) it did
    /// not, so the assertion ran first. That is what made five tests across three suites fail at
    /// random, about one run in three.
    public func waitForIdleForTesting() async {
        await waitForIdle(awaitingLoad: true)
    }

    /// The same, for a test that is deliberately holding the load open.
    ///
    /// `PlayerEpisodeSwapTests` gates the injected unrestrict so the swap window — switched to the
    /// new episode, engine still on the old file — stays wide for the length of the test. Waiting
    /// for that load to finish would be waiting for the test to move on, and the test is waiting
    /// for this: both stop. Everything else still settles.
    public func waitForIdleWhileLoadIsHeldForTesting() async {
        await waitForIdle(awaitingLoad: false)
    }

    private func waitForIdle(awaitingLoad: Bool) async {
        await Task.yield()
        // The load chain — resume lookup, unrestrict, `engine.load`, the early resume seek — is a
        // real, finite task. Every "(engine.seeks → []) == [615]" and "loadedAudioLanguage → nil"
        // failure was this task simply not having run yet.
        if awaitingLoad { await loadTask?.value }
        // Engine events are consumed by a long-lived loop that cannot be awaited, so the signal is
        // the count: wait until it has handled everything the engine has handed it.
        //
        // Only while that loop is actually running. A model the test never `start()`ed has no
        // consumer, and one whose engine has been stopped has a finished stream — in both cases
        // events are emitted and never handled, and waiting for a count that cannot move would
        // stall every call until the deadline.
        if eventTask != nil, let counting = engine as? EventCountingEngineForTesting {
            await waitForTestingCondition {
                self.eventLoopFinished || self.handledEventCount >= counting.yieldedEventCount
            }
        }
        // `.ended` is handled by spawning `finish()`, so handling the event is not the same as the
        // file having finished.
        await finishTask?.value
        // …and a tick starts the progress write without awaiting it, on purpose.
        await progressSaveTask?.value
        // A handler can start a new load (retry, the next episode) — let that one land too.
        if awaitingLoad { await loadTask?.value }
    }

    /// Poll `condition` until it holds. The polling interval is not load-bearing: the condition is
    /// the signal, and the deadline only exists so a genuine hang fails the test instead of the
    /// run. Yields first — on the main actor that is usually enough — then backs off to short
    /// sleeps so waiting on slow awaited work does not burn a core.
    private func waitForTestingCondition(_ condition: () -> Bool) async {
        if condition() { return }
        for _ in 0..<64 {
            await Task.yield()
            if condition() { return }
        }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
            if condition() { return }
        }
    }

    /// Test seam: the one-shot subtitle download fallback is deliberately deferred, so it is a real
    /// task to await rather than a delay to sleep past.
    public func waitForSubtitleFallbackForTesting() async {
        await waitForIdleForTesting()
        await subtitleFallbackTask?.value
        await waitForIdleForTesting()
    }

    /// Test seam: perform a full scrub cycle to `seconds` in one call.
    /// Test seam: the window auto-sync listens to is chosen from the media's length, which only a
    /// real engine reports.
    func setDurationForTesting(_ seconds: Double) { duration = seconds }

    func commitScrubForTesting(to seconds: Double) {
        beginScrub()
        updateScrub(by: seconds - scrubTarget)
        commitScrub()
    }
}

/// A test engine that can say how many events it has handed to the model.
///
/// The model consumes engine events in a long-lived loop, which cannot be awaited — so this count
/// is what `waitForIdleForTesting` compares against to know an emitted event has been HANDLED,
/// instead of sleeping and hoping. The real engine does not conform; nothing in the app reads it.
@MainActor
protocol EventCountingEngineForTesting: AnyObject {
    var yieldedEventCount: Int { get }
}
