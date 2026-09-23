import Foundation
import Observation

/// Whether the windowed HUD (top bar + panel, plus the cursor and the traffic lights) is on
/// screen. `PlayerScreen` owns one; pointer movement and every key command `poke()` it, which shows
/// it and re-arms a single auto-hide timer. Only `poke()` arms that timer — the four inputs below
/// merely decide whether an armed timer is ALLOWED to actually hide it, and showing the HUD the
/// instant one of them starts blocking hiding (pausing, a panel opening, the pointer landing on a
/// control, a scrub starting) needs no timer at all.
@MainActor
@Observable
final class HUDVisibility {
    private(set) var isVisible = true

    var isPlaying = false { didSet { showIfNowBlocked() } }
    var pointerOverControls = false { didSet { showIfNowBlocked() } }
    var panelOpen = false { didSet { showIfNowBlocked() } }
    var isScrubbing = false { didSet { showIfNowBlocked() } }
    /// Set by `PlayerScreen` from `WindowRef.isFullScreen`. Picks which of
    /// `PlayerHUDMetrics.autoHideDelay`'s two delays the next `poke()` arms — full screen's compact
    /// bar hides sooner than the windowed panel.
    var isFullScreen = false

    /// Whether `poke()` is allowed to arm a timer at all. true only for the harness's
    /// `HUDVisibility(delay: nil)`, which must never hide on its own.
    private let pinned: Bool
    private var hideTask: Task<Void, Never>?

    init(delay: Duration? = .seconds(2.9)) {
        self.pinned = delay == nil
    }

    /// Shows the HUD and re-arms the one auto-hide timer, at whichever delay the current
    /// presentation (windowed vs full screen) calls for.
    func poke() {
        isVisible = true
        hideTask?.cancel()
        guard !pinned else { hideTask = nil; return }
        let delay = PlayerHUDMetrics.autoHideDelay(isFullScreen: isFullScreen)
        armedDelayForTesting = delay
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.hideIfAllowed()
        }
    }

    /// Hides only when nothing is blocking it right now. Called by the armed timer, and safe to call
    /// directly (a test does, to avoid a sleep-based test).
    func hideIfAllowed() {
        guard canHide else { return }
        isVisible = false
    }

    private var canHide: Bool {
        isPlaying && !pointerOverControls && !panelOpen && !isScrubbing
    }

    private func showIfNowBlocked() {
        guard !canHide else { return }
        isVisible = true
        hideTask?.cancel()
        hideTask = nil
    }

    /// Test seam: whether a hide timer is currently armed — the synchronous half of "a pinned HUD
    /// never arms a timer" (the rest is that a real sleep-based test would need to prove nothing
    /// ever fires, which this codebase does not do).
    var isTimerArmedForTesting: Bool { hideTask != nil }

    /// Test seam: the delay the most recent `poke()` armed, without a real sleep — proves
    /// `isFullScreen` picked the right one of `PlayerHUDMetrics.autoHideDelay`'s two delays.
    private(set) var armedDelayForTesting: Duration?
}
