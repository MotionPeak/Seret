import Foundation
import DebridCore

extension PlayerModel {

    // MARK: - Lifecycle

    /// Called once when the player appears. Starts the long-lived event loop (the single consumer of
    /// the engine's AsyncStream) and loads the first source. retry()/tryAnotherVersion() re-load
    /// WITHOUT relaunching the loop, so the single VLCKit stream is consumed continuously across
    /// source switches.
    ///
    /// Idempotent, because it is wired to the player screen's `.onAppear` and SwiftUI fires that
    /// again on every re-appearance (a cover dismissing above it, a re-parented stack). A second
    /// pass would `reload()` — throwing the viewer back to the start of the film mid-watch — and
    /// re-register the Now Playing commands, doubling every press the iPhone Remote sends. Since
    /// retry/tryAnotherVersion never come through here, the guard can be this blunt.
    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        eventTask = Task { await self.consumeEvents() }
        activateNowPlaying()
        reload()
    }

    func consumeEvents() async {
        for await event in engine.events {
            switch event {
            case .state(let s): handle(state: s)
            case .time(let t): await tick(t)
            case .tracksChanged: refreshTracks()
            }
        }
    }

    func handle(state: PlaybackState) {
        switch state {
        case .idle, .buffering:
            // VLCKit emits .buffering even after playback has started; don't let it revert an
            // active session's phase (that flashed the overlay over the video). It does mean we're
            // waiting on frames — flag buffering so the UI shows a small inline hint (the full
            // overlay only shows before the first frame).
            // …but NOT while paused. VLCKit keeps emitting `.buffering` after a pause, and a paused
            // player never emits `.playing` again, so nothing was left to lower the hint: the
            // spinner simply stuck under a stopped picture.
            if phase != .paused { isBuffering = true }
            if phase != .playing && phase != .paused { phase = .buffering }
        case .playing:
            phase = .playing
            markRendered()
            refreshTracks()
            armAutoHide()
            pushNowPlaying()          // rate changed — the system cannot infer that itself
        case .paused:
            phase = .paused
            isBuffering = false
            controlsVisible = true            // a paused viewer is looking — keep controls up
            hideControlsTask?.cancel()
            // A `.paused` means the media is OPEN and a frame is on screen — VLCKit renders the
            // first frame when it pauses. Without this the full-screen overlay stays up over a
            // ready video and the only escape is the hardware Play button (the reported bug).
            // Guarded on `isSwitching` so the OUTGOING media's late `.paused` during an episode
            // swap can't clear the swap guard early and let a stale `.ended` auto-advance.
            if !isSwitching { markRendered() }
            // A paused player emits no more time events, so this is the ONLY chance to tell the
            // system playback stopped — without it the Remote app keeps advancing a frozen playhead.
            pushNowPlaying()
        case .ended:
            Task { await finish() }
        case .failed(let reason):
            phase = .failed(reason)
        }
    }

    func tick(_ t: PlaybackTime) async {
        // Until the engine has been handed THIS load's media, every time event still belongs to the
        // outgoing file (see `engineHoldsCurrentMedia`). Not even the duration may be taken from
        // one: `upNextThreshold` is derived from it, so a stale duration re-arms the Up Next bar.
        guard engineHoldsCurrentMedia else { return }
        duration = t.duration


        // Resume: the load path already issued a best-effort seek. Arrival is checked FIRST so
        // that when VLC honored it (first ticks land at the point) no second seek fires; when it
        // was dropped (ticks start near 0) the deferred seek is issued ONCE here — a tick means
        // VLCKit has parsed the media and will now honor it. The loading overlay stays up until
        // the playhead actually reaches the point, so the bar never flashes 0 and jumps.
        if resumeTarget > 0 {
            if duration > 0, resumeTarget >= duration {
                // The saved point can be at/beyond THIS source's length — a shorter re-encode of the
                // same title shares the contentKey. Seeking to/past EOF lands at the end (instant
                // "ended" or a stuck buffer). Drop it and start from 0. NO slack band here: a
                // legitimate resume a few seconds before the real end must still be honored (VLCKit
                // can report a slightly-low early duration estimate, and a band would false-drop it).
                resumeTarget = 0
            } else if t.position >= resumeTarget - 5 {  // arrived (keyframe slack) → resume complete
                lastTickPosition = t.position
                resumeTarget = 0
            } else if !resumeSeekIssued {
                engine.seek(to: resumeTarget)
                resumeSeekIssued = true
                resumeTicksSinceSeek = 0
            } else {
                resumeTicksSinceSeek += 1
                if resumeTicksSinceSeek >= resumeArrivalGraceTicks {
                    // The seek landed short of the slack band and will never "arrive". Accept the
                    // playhead where it is so the overlay can clear — a resume a few seconds early
                    // is fine; a permanently-black screen is not.
                    lastTickPosition = t.position
                    resumeTarget = 0
                    return
                }
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
            if abs(t.position - seek.to) < abs(t.position - seek.from) {
                pendingSeek = nil                       // landed → resume live tracking
                pendingSeekTicks = 0
                isBuffering = false                     // …and the loading hint comes down
            } else {
                // libvlc can DROP a seek (an unseekable stretch, a stalled socket) and then no tick
                // ever lands nearer the target. Waiting forever froze the bar at a time the film
                // never reached and stopped progress being written for the rest of the session, so
                // give up after a bounded wait and follow the real playhead again.
                pendingSeekTicks += 1
                guard pendingSeekTicks >= pendingSeekGraceTicks else { return }
                pendingSeek = nil
                pendingSeekTicks = 0
                isBuffering = false
            }
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
        // `abs`, because the old forward-only test meant a rewind wrote nothing again until the
        // playhead had climbed all the way back — so leaving after a rewind resumed at the point
        // the viewer had rewound FROM.
        //
        // And fire-and-forget, because this runs inside the single event-consumption loop: the real
        // closure is a SwiftData write behind an actor, and awaiting it here
        // stalled every time update and state change behind it — the scrub bar froze and the
        // transport stopped answering for the length of the request. One write at a time, so they
        // can neither pile up nor land out of order.
        if abs(position - lastSavedPosition) >= saveInterval, !isSavingProgress {
            lastSavedPosition = position
            isSavingProgress = true
            let (key, source, at, length) = (contentKey, WatchKey.source(currentSource), position, duration)
            Task { @MainActor [weak self] in
                await self?.recordProgress(key, source, at, length)
                self?.isSavingProgress = false
            }
        }
        maybeShowUpNext()
        pushNowPlaying()
    }

    func reload() {
        phase = .preparing
        position = 0
        duration = 0
        hasRenderedFrame = false
        isBuffering = true
        lastTickPosition = 0
        engineHoldsCurrentMedia = false   // the engine still holds the OUTGOING media until load()
        // The request's resumeAt is only the FALLBACK — loadCurrentSource() re-resolves the
        // saved position from the store (when a provider is wired) so resume can't race the
        // screen's watch-state load or go stale after a previous playback.
        resumeTarget = fromStart ? 0 : max(resumeAt ?? 0, 0)
        resumeSeekIssued = false
        resumeTicksSinceSeek = 0
        pendingSeek = nil
        pendingSeekTicks = 0
        isFinishing = false     // a new media may end again
        cancelScan()            // a hold that outlived the swap would travel through the NEW media
        cancelCoalescedSeek()
        // libvlc's track ids are POSITIONAL ("audio/0", "spu/0") and so collide between two releases
        // of the same title. Leaving the mirrored ids set made the preference matcher compare the
        // new media's track against the old id, find them equal, and never tell the engine — so
        // "Try another version" played with subtitles off while the panel still showed them ticked.
        selectedAudioID = nil
        selectedSubtitleID = nil
        audioPickedByUser = false          // a new source re-decides audio from scratch
        audioSelectionSignature = []
        subtitlePickedByUser = false       // …and so does the subtitle choice
        subtitleSelectionSignature = []
        subtitleFallbackRequested = false
        subtitleOffAsserted = false
        subtitleFallbackTask?.cancel()
        subtitleFallbackTask = nil
        subtitleAttachTimeoutTask?.cancel()   // an orphan would fire against the NEW media's attach
        subtitleAttachTimeoutTask = nil
        lastSavedPosition = -.infinity
        loadTask?.cancel()
        loadTask = Task { await self.loadCurrentSource() }
    }

    func loadCurrentSource() async {
        do {
            // The resume lookup first (a local store read, single-digit ms), then unrestrict —
            // which is instant anyway when the link was prefetched (PlayableLinkCache).
            if !fromStart, let resolveResume {
                let saved = await resolveResume(contentKey) ?? 0
                resumeTarget = saved > 0 ? saved : 0     // authoritative: overrides the UI hint
            }
            let url = try await unrestrict(currentSource.restrictedLink)
            guard !Task.isCancelled else { return }   // superseded by a newer reload()
            engine.load(url: url, headers: [:], audioLanguage: preferredAudioLanguageOption,
                        audioTrackID: rememberedAudioTrackID)
            engineHoldsCurrentMedia = true   // from here, time events describe THIS source
            engine.play()
            armLoadWatchdog()
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

    /// First frames are on screen. Clears the loading state so the overlay/spinner hide.
    func markRendered() {
        hasRenderedFrame = true
        isBuffering = false
        loadWatchdog?.cancel()     // the load succeeded — disarm the timeout
        loadWatchdog = nil
        isSwitching = false        // the new episode's media is on screen → end events are real again
    }

    /// Arm the load watchdog. Disarmed by `markRendered()` (first frame) and `teardown()`.
    func armLoadWatchdog() {
        loadWatchdog?.cancel()
        loadWatchdog = Task { @MainActor [weak self] in
            guard let timeout = self?.loadTimeout else { return }
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, let self, !self.hasRenderedFrame else { return }
            if case .failed = self.phase { return }     // already failed for a better reason
            self.phase = .failed("This stream didn't start. The Real-Debrid link may have expired.")
        }
    }

    func finish() async {
        guard phase != .ended else { return }   // VLCKit can emit .stopped + .ended; finish once
        guard !isSwitching else { return }      // ignore the OLD media's late `.ended` mid-swap
        // Both of those guards read state that only changes AFTER the await below, and VLCKit
        // reports the end of a file twice (`.stopping` then `.stopped` — the engine folds both into
        // `.ended`), so two Tasks got past them and both advanced: the viewer finished E1 and landed
        // on E3. This latch closes synchronously, before any suspension point. `reload()` clears it,
        // which covers every path that legitimately re-arms an ending.
        guard !isFinishing else { return }
        isFinishing = true
        // VLCKit maps BOTH end-of-file and a failed open to `.stopped`/`.stopping` → `.ended`.
        // A media that never rendered a frame and never moved the playhead did not END — it never
        // STARTED. Treating that as EOF records progress at 0 and silently auto-advances to the
        // next episode with no error and no Retry.
        if !hasRenderedFrame, position < 1 {
            phase = .failed("The stream stopped before it started. The Real-Debrid link may have expired.")
            return
        }
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

    // MARK: - Recovery

    public func retry() { reload() }

    public func tryAnotherVersion() {
        guard sourceIndex + 1 < sources.count else { return }
        sourceIndex += 1
        reload()
    }

    // MARK: - Teardown

    public func teardown() async {
        eventTask?.cancel()
        loadTask?.cancel()
        hideControlsTask?.cancel()
        scrubBarHideTask?.cancel()
        upNextTask?.cancel()
        seekDispatchTask?.cancel()
        loadWatchdog?.cancel()
        subtitleFallbackTask?.cancel()          // else it spends OpenSubtitles quota on a dead engine
        subtitleAttachTimeoutTask?.cancel()
        cancelScan()
        nowPlaying?.deactivate()
        // Stop the picture and sound FIRST. `recordCurrentProgress()` is a store write, and awaiting
        // it before this left the film's audio playing over the Detail page for as long as it took
        // — which, when this closure still went to Trakt, was up to URLSession's 60s timeout. It
        // reads only model state (`position`/`duration`), never the engine, so stopping first
        // records exactly the same values.
        engine.stop()
        await recordCurrentProgress()
    }
}
