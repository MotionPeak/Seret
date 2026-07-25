import Foundation
import DebridCore

extension PlayerModel {

    // MARK: - Transport controls

    public func togglePlayPause() {
        if phase == .playing { engine.pause() } else { engine.play() }
        revealScrubBar()
    }

    public func skip(_ delta: Double) {
        let before = position
        let origin = pendingSeek?.from ?? position   // a burst keeps the ORIGINAL pre-seek origin
        let target = clamp(position + delta)
        handleUserSeek(to: target)
        position = target            // optimistic: the scrub bar jumps to the new time immediately
        isBuffering = true           // …and shows the loading hint while the seek rebuffers
        lastTickPosition = target    // re-arm advance detection past the target
        pendingSeek = target != origin ? (from: origin, to: target) : nil   // hold the bar through stale ticks
        scheduleCoalescedSeek(to: target)
        accumulateSkipFeedback(target - before)         // this tap's real jump feeds the indicator
    }
    public func scrub(to seconds: Double) {
        let target = clamp(seconds)
        handleUserSeek(to: target)
        engine.seek(to: target)
    }

    /// Shared bookkeeping for a deliberate user-initiated seek (skip / scrub commit / direct scrub):
    /// (1) supersede any still-in-flight resume so tick()'s resume branch can't drag the playhead back
    ///     to the resume point (or freeze the displayed position), and (2) if the seek lands the
    ///     playhead back before the Up Next threshold, cancel the auto-advance countdown so it can't
    ///     yank the viewer to the next episode mid-scene.
    func handleUserSeek(to target: Double) {
        if resumeTarget > 0 { resumeTarget = 0; resumeSeekIssued = true }
        if upNextVisible, let threshold = upNextThreshold, target < threshold {
            upNextTask?.cancel()
            upNextVisible = false
            upNextSecondsRemaining = 0
            // leave upNextDismissed untouched; re-crossing the threshold re-arms via maybeShowUpNext()
        }
    }

    /// Grow the on-screen skip indicator by this tap's ACTUAL jump, so ONE badge counts up across a
    /// rapid burst (10 → 20 → 30 → 1:10…). The running total resets only after ~0.8s without another
    /// tap — NOT when a seek lands — so fast repeats keep climbing instead of popping back to 10.
    func accumulateSkipFeedback(_ applied: Double) {
        guard applied != 0 else { return }              // a no-op tap at an edge leaves the badge alone
        let total = (skipFeedback?.seconds ?? 0) + applied
        skipFeedback = total == 0 ? nil : SkipFeedback(seconds: total, id: (skipFeedback?.id ?? 0) &+ 1)
        skipFeedbackClearTask?.cancel()
        guard skipFeedback != nil else { return }
        skipFeedbackClearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            skipFeedback = nil
        }
    }

    /// See `seekCoalesceWindow`: leading seek fires immediately, skips landing inside the open
    /// window only retarget, and one trailing seek issues the final target when it closes.
    func scheduleCoalescedSeek(to target: Double) {
        coalescedSeekTarget = target
        guard seekDispatchTask == nil else { return }   // window open → the trailing pass handles it
        engine.seek(to: target)
        dispatchedSeekTarget = target
        seekGeneration &+= 1
        let generation = seekGeneration
        seekDispatchTask = Task { @MainActor in
            // Only this window may clear the slot, and only while it is still the current one —
            // a cancelled predecessor's cleanup must not evict a live successor.
            defer { if seekGeneration == generation { seekDispatchTask = nil } }
            try? await Task.sleep(for: .seconds(seekCoalesceWindow))
            guard !Task.isCancelled, seekGeneration == generation else { return }
            if let final = coalescedSeekTarget, final != dispatchedSeekTarget {
                engine.seek(to: final)
            }
            coalescedSeekTarget = nil
            dispatchedSeekTarget = nil
        }
    }

    /// Drop any open coalescing window (a direct seek — scrub commit / reload — supersedes it).
    func cancelCoalescedSeek() {
        seekDispatchTask?.cancel()
        seekDispatchTask = nil
        seekGeneration &+= 1                            // orphan the cancelled task's cleanup
        coalescedSeekTarget = nil
        dispatchedSeekTarget = nil
    }

    /// Clamp a time to `[0, duration]` (duration may be 0 before it is known).
    func clamp(_ t: Double) -> Double {
        let upper = duration > 0 ? duration : max(0, t)
        return min(max(0, t), upper)
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
        handleUserSeek(to: scrubTarget)
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

    /// Hold-to-scan: holding left/right travels through the film at an accelerating rate.
    ///
    /// Implemented as accelerating repeated SKIPS rather than a negative playback rate, because
    /// libvlc has no reliable reverse playback — a negative rate simply does nothing backwards,
    /// so the two directions would behave differently. Repeated seeks are symmetric, and they
    /// reuse the existing coalescing and the accumulating on-screen badge, so a hold reads as one
    /// growing jump instead of a stutter of separate ones.
    public func beginScan(direction: Double) {
        scanTask?.cancel()
        revealScrubBar()
        scanTask = Task { @MainActor [weak self] in
            var step = 10.0
            while !Task.isCancelled {
                guard let self else { return }
                self.skip(direction >= 0 ? step : -step)
                try? await Task.sleep(for: .seconds(0.5))
                step = min(step * 1.6, 120)      // 10 → 16 → 26 → 41 … capped at two minutes
            }
        }
    }

    /// Release the scan.
    public func endScan() {
        scanTask?.cancel()
        scanTask = nil
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

    // MARK: - Controls auto-hide

    /// Reveal the transport and re-arm the auto-hide timer. Called on every user interaction.
    public func showControls() {
        controlsVisible = true
        armAutoHide()
    }

    /// Hide the transport after `autoHideDelay` of no interaction — but only while actively playing
    /// and not scrubbing (paused / buffering / error keep the controls up).
    func armAutoHide() {
        hideControlsTask?.cancel()
        guard autoHideDelay > 0 else { return }
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(autoHideDelay))
            guard !Task.isCancelled else { return }
            if phase == .playing, !isScrubbing { controlsVisible = false }
        }
    }
}
