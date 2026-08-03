import Foundation
import DebridCore

extension PlayerModel {

    // MARK: - Lifecycle

    /// Called once when the player appears. Starts the long-lived event loop (the single consumer of
    /// the engine's AsyncStream) and loads the first source. retry()/tryAnotherVersion() re-load
    /// WITHOUT relaunching the loop, so the single VLCKit stream is consumed continuously across
    /// source switches.
    public func start() {
        eventTask?.cancel()
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
            if let onScrobbleStart {
                let f = currentFraction
                Task { await onScrobbleStart(f) }   // the scrobbler dedups repeat starts
            }
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
            if let onScrobblePause {
                let f = currentFraction
                Task { await onScrobblePause(f) }
            }
        case .ended:
            Task { await finish() }
        case .failed(let reason):
            phase = .failed(reason)
        }
    }

    func tick(_ t: PlaybackTime) async {
        duration = t.duration

        // A fractional resume (Trakt stores a percentage) becomes a real seek target the moment the
        // media reports its length — this is the earliest point seconds are computable. From here the
        // existing resumeTarget path below owns the seek/arrival handling unchanged.
        if resumeFraction > 0, t.duration > 0 {
            resumeTarget = resumeFraction * t.duration
            resumeFraction = 0
        }

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
            guard abs(t.position - seek.to) < abs(t.position - seek.from) else { return }
            pendingSeek = nil                           // landed → resume live tracking
            isBuffering = false                         // …and the loading hint comes down
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
        pushNowPlaying()
    }

    func reload() {
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
        resumeTicksSinceSeek = 0
        resumeFraction = 0
        pendingSeek = nil
        cancelCoalescedSeek()
        trackPrefsApplied = false
        audioPickedByUser = false          // a new source re-decides audio from scratch
        audioSelectionSignature = []
        lastSavedPosition = -.infinity
        loadTask?.cancel()
        loadTask = Task { await self.loadCurrentSource() }
    }

    func loadCurrentSource() async {
        do {
            // The resume lookup first (a local store read, single-digit ms), then unrestrict —
            // which is instant anyway when the link was prefetched (PlayableLinkCache).
            if !fromStart, let resolveResumeFraction {
                // Fractional backend (Trakt): stash the fraction; tick() turns it into a seek
                // target as soon as the media reports a duration (it's 0 here).
                let f = await resolveResumeFraction(contentKey) ?? 0
                resumeFraction = (f > 0 && f < 1) ? f : 0
                resumeTarget = 0
            } else if !fromStart, let resolveResume {
                let saved = await resolveResume(contentKey) ?? 0
                resumeTarget = saved > 0 ? saved : 0     // authoritative: overrides the UI hint
            }
            let url = try await unrestrict(currentSource.restrictedLink)
            guard !Task.isCancelled else { return }   // superseded by a newer reload()
            engine.load(url: url, headers: [:])
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
        scanTask?.cancel()
        nowPlaying?.deactivate()
        await recordCurrentProgress()
        engine.stop()
    }
}
