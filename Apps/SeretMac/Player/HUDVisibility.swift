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

    /// nil = pinned (the harness): `poke()` shows it and never arms a timer, so it can never hide.
    private let delay: Duration?
    private var hideTask: Task<Void, Never>?

    init(delay: Duration? = .seconds(2.9)) {
        self.delay = delay
    }

    /// Shows the HUD and re-arms the one auto-hide timer.
    func poke() {
        isVisible = true
        hideTask?.cancel()
        guard let delay else { hideTask = nil; return }
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
}
