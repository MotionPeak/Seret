import SwiftUI
import UIKit
import QuartzCore

/// Every remote input the player takes while watching, on ONE non-focusable UIKit surface.
///
/// Why UIKit and why non-focusable: a *focusable* view lets the tvOS focus engine consume
/// touch-surface swipes to move focus before any pan recognizer sees them — that is the real
/// reason "touch-scrub" and "reliable directional clicks" kept trading places in this file's
/// history (see the ScrubPad saga in git). `AVPlayerViewController` runs both pipelines because
/// it is non-focusable UIKit with no focusable siblings at rest. So does this.
///
/// Recognizers run simultaneously (`shouldRecognizeSimultaneouslyWith`):
///   • a zero-duration long-press on `.indirect` touches → fires the instant the thumb lands (wake)
///   • a pan on `.indirect` touches → the scrub drag
///   • press-type taps for the four arrows and select → ±10s, bar, panel, play/pause
///   • press-type long-presses on left/right → hold-to-scan
///
/// `isActive` is false whenever a focusable overlay (settings panel, episode strip, Up Next) is
/// on screen, so exactly one system owns focus at any moment.
struct PlayerInputSurface: UIViewRepresentable {
    var isActive: Bool
    /// Whether a horizontal swipe is allowed to scrub. Derived from the player being PAUSED rather
    /// than tracked here, so it stays right no matter how the pause happened — touchpad click, the
    /// remote's dedicated play/pause button, Siri, or the iPhone Remote.
    ///
    /// Why gate it at all: previously any swipe entered scrub mode and committed a seek on lift, so
    /// simply resting or sliding a thumb while watching would jump the film. Click now pauses AND
    /// arms; swipe to move; click again to resume where you left it.
    var scrubEnabled: Bool = true

    /// Thumb landed on the glass — reveal the bar. Playback keeps running.
    var onTouchDown: () -> Void
    /// Thumb lifted without ever crossing the scrub threshold.
    var onTouchUp: () -> Void
    /// Horizontal drag crossed the threshold — enter scrub mode.
    var onScrubBegan: () -> Void
    /// Total horizontal displacement from the gesture origin, in points.
    var onScrubMoved: (Double) -> Void
    /// Thumb lifted while scrubbing — commit the seek.
    var onScrubEnded: () -> Void
    /// Gesture cancelled by the system — abandon without seeking.
    var onScrubCancelled: () -> Void

    var onSkip: (Double) -> Void
    var onSelect: () -> Void
    /// The remote's DEDICATED play/pause button — a different press type from `.select`, and a
    /// different delivery path from every gesture here.
    ///
    /// It lives on this surface rather than on SwiftUI's `.onPlayPauseCommand` because that
    /// modifier fires only while SwiftUI's own focus system owns the focused view, and since this
    /// surface became focusable (it received nothing at all otherwise) the focused view is a UIKit
    /// one. The button did nothing on the Siri Remote AND in the iPhone Remote app, which both send
    /// this same press.
    var onPlayPause: () -> Void
    var onUp: () -> Void
    var onDown: () -> Void
    /// Hold-to-scan started in a direction (-1 back, +1 forward), and released.
    var onScanBegan: (Double) -> Void
    var onScanEnded: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = InputView()
        view.backgroundColor = .clear
        context.coordinator.install(on: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.setActive(isActive)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// Focusable **while the player owns the remote** — and that is load-bearing.
    ///
    /// This used to return `false` unconditionally, on the theory that a focusable view lets the
    /// focus engine consume touch-surface swipes before any pan recogniser sees them. The input
    /// probe disproved it: with `canBecomeFocused = false` this view received **nothing** — not
    /// indirect touches, not even button presses (TOUCH 0 / PRESS 0 after a six-press volley, while
    /// Menu still worked because SwiftUI handles that on the view hierarchy). A view tvOS cannot
    /// focus is simply not in the delivery path for remote input, so the whole surface was inert.
    ///
    /// The focus-steals-swipes worry is real but only bites when focus has somewhere to GO. At rest
    /// the player has no other focusable view (the transport bar and episode peek are both
    /// `allowsHitTesting(false)`), so the engine has no candidate and the pan recogniser keeps the
    /// gesture. When an overlay that owns focus appears — settings panel, episode strip, Up Next —
    /// `isActive` goes false and this stops being focusable, so exactly one system owns focus at a
    /// time.
    final class InputView: UIView {
        /// Mirrors `isActive`; toggled by the coordinator so overlays can take focus cleanly.
        var focusable = true { didSet { if focusable != oldValue { setNeedsFocusUpdate() } } }
        override var canBecomeFocused: Bool { focusable }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PlayerInputSurface
        private var recognizers: [UIGestureRecognizer] = []
        /// The surface itself, so focusability can follow `isActive`.
        private weak var view: InputView?
        /// Horizontal displacement at which a drag stops being a stray thumb-rest and becomes a
        /// scrub. Low enough to feel immediate, high enough that a click doesn't scrub.
        private let scrubThreshold: CGFloat = 20
        /// Vertical travel that counts as a deliberate up/down swipe. Higher than the scrub
        /// threshold: a thumb drifting off-axis mid-scrub must not open the panel.
        private let swipeThreshold: CGFloat = 45
        private var isScrubbing = false
        /// One vertical action per drag — a long swipe must not fire `onDown` repeatedly.
        private var verticalFired = false
        /// A hold-to-scan is running. Tracked here (not just in the model) because this surface is
        /// what learns the gesture ended — including when it ends by the surface being deactivated.
        private var isScanning = false
        /// When the last scan ended. A hold fires the long-press AND, on release, the tap for the
        /// same arrow; without a short guard every scan landed a stray ±10s on top of itself.
        private var lastScanEndedAt: CFTimeInterval = -.greatestFiniteMagnitude
        /// How long after a scan a same-arrow tap is treated as that scan's release, not a new tap.
        private let scanTapGuard: CFTimeInterval = 0.3

        init(parent: PlayerInputSurface) { self.parent = parent }

        func install(on view: InputView) {
            self.view = view
            // Wake: zero-duration long-press fires .began the instant the thumb lands. A pan
            // cannot do this — it needs movement first.
            let wake = UILongPressGestureRecognizer(target: self, action: #selector(handleWake(_:)))
            wake.minimumPressDuration = 0
            wake.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]

            recognizers = [wake, pan]

            let taps: [(UIPress.PressType, Selector)] = [
                (.leftArrow, #selector(handleLeft)),
                (.rightArrow, #selector(handleRight)),
                (.upArrow, #selector(handleUp)),
                (.downArrow, #selector(handleDown)),
                (.select, #selector(handleSelect)),
                (.playPause, #selector(handlePlayPause)),
            ]
            recognizers += taps.map { type, action in
                let tap = UITapGestureRecognizer(target: self, action: action)
                tap.allowedPressTypes = [NSNumber(value: type.rawValue)]
                return tap
            }

            // Hold-to-scan: the native tvOS contract (2x/3x/4x the longer you hold).
            let holds: [(UIPress.PressType, Selector)] = [
                (.leftArrow, #selector(handleScanBack(_:))),
                (.rightArrow, #selector(handleScanForward(_:))),
            ]
            recognizers += holds.map { type, action in
                let hold = UILongPressGestureRecognizer(target: self, action: action)
                hold.allowedPressTypes = [NSNumber(value: type.rawValue)]
                hold.minimumPressDuration = 0.6
                return hold
            }

            for recognizer in recognizers {
                recognizer.delegate = self
                view.addGestureRecognizer(recognizer)
            }
        }

        func setActive(_ active: Bool) {
            for recognizer in recognizers { recognizer.isEnabled = active }
            // Hand focus to whichever system should own it: the surface while watching, the
            // overlay otherwise. `focusable` only requests an update when it actually changes.
            view?.focusable = active
            guard !active else { return }
            if isScrubbing {
                isScrubbing = false
                parent.onScrubCancelled()
            }
            // End a running scan too. This is the bug behind "skip keeps forwarding uncontrollably":
            // only the scrub was cancelled here, so when an overlay took the remote mid-hold — Up
            // Next, the settings panel, the episode strip — the recognisers were disabled and the
            // release never arrived, leaving the model's scan loop skipping forever. Scanning to the
            // end of a film RAISES the Up Next bar, so the runaway triggered its own trigger.
            endScanIfRunning()
        }

        /// Stop a hold-to-scan exactly once, and remember when, so the release tap is not counted
        /// as a fresh skip.
        private func endScanIfRunning() {
            guard isScanning else { return }
            isScanning = false
            lastScanEndedAt = CACurrentMediaTime()
            parent.onScanEnded()
        }

        // Every recognizer here is a different input channel — none should starve another.
        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        @objc private func handleWake(_ g: UILongPressGestureRecognizer) {
            #if DEBUG
            InputProbe.shared.touch("wake .\(g.state.rawValue)")
            #endif
            switch g.state {
            case .began:
                parent.onTouchDown()
            case .ended, .cancelled, .failed:
                if !isScrubbing { parent.onTouchUp() }
            default:
                break
            }
        }

        @objc private func handlePan(_ g: UIPanGestureRecognizer) {
            let translation = g.translation(in: g.view)
            let dx = translation.x
            let dy = translation.y
            #if DEBUG
            InputProbe.shared.touch("pan .\(g.state.rawValue)", dx: Double(dx))
            #endif
            switch g.state {
            case .began:
                verticalFired = false
            case .changed:
                // A VERTICAL swipe is its own gesture, not a failed horizontal one. Until now only
                // `dx` was read, so swiping down did nothing at all — the settings panel was
                // reachable only by clicking the touchpad's bottom edge, which is why "swipe down
                // for subtitles" appeared dead. Claim the gesture once per drag, and only when the
                // motion is clearly more vertical than horizontal, so a sloppy scrub is not stolen.
                if !isScrubbing, !verticalFired,
                   abs(dy) >= swipeThreshold, abs(dy) > abs(dx) * 1.5 {
                    verticalFired = true
                    if dy > 0 { parent.onDown() } else { parent.onUp() }
                    return
                }
                guard !verticalFired else { return }

                // Only a PAUSED player scrubs. While playing, a swipe still wakes the transport bar
                // (the long-press recogniser does that on touch-down) but never seeks.
                if !isScrubbing, parent.scrubEnabled, abs(dx) >= scrubThreshold {
                    isScrubbing = true
                    #if DEBUG
                    InputProbe.shared.scrubBegan()
                    #endif
                    parent.onScrubBegan()
                }
                if isScrubbing { parent.onScrubMoved(Double(dx)) }
            case .ended:
                verticalFired = false
                if isScrubbing { isScrubbing = false; parent.onScrubEnded() }
            case .cancelled, .failed:
                verticalFired = false
                if isScrubbing { isScrubbing = false; parent.onScrubCancelled() }
            default:
                break
            }
        }

        // A left/right tap nudges the scrub target while scrubbing and skips otherwise — the
        // caller decides which; it only needs the signed amount.
        @objc private func handleLeft()  { probePress("left");  skipUnlessScanning(-10) }
        @objc private func handleRight() { probePress("right"); skipUnlessScanning(10) }

        /// A held arrow drives the long-press (scan) AND fires this tap on release, so the tap has
        /// to stand down for the scan's own release. Time-based rather than ordered, because UIKit
        /// makes no promise about which of two simultaneous recognisers reports first.
        private func skipUnlessScanning(_ delta: Double) {
            guard !isScanning, CACurrentMediaTime() - lastScanEndedAt > scanTapGuard else { return }
            parent.onSkip(delta)
        }
        /// Unlike `.select`, this never commits a scrub — the viewer reaching for play/pause is
        /// asking about playback, not about the marker they are aiming with.
        @objc private func handlePlayPause() { probePress("playPause"); parent.onPlayPause() }
        @objc private func handleUp()    { probePress("up");    parent.onUp() }
        @objc private func handleDown()  { probePress("down");  parent.onDown() }
        @objc private func handleSelect() {
            probePress("select")
            if isScrubbing { isScrubbing = false; parent.onScrubEnded() }   // click commits early
            else { parent.onSelect() }
        }

        /// No-op in release; the probe compiles out entirely.
        private func probePress(_ name: String) {
            #if DEBUG
            InputProbe.shared.press(name)
            #endif
        }

        @objc private func handleScanBack(_ g: UILongPressGestureRecognizer) { scan(g, direction: -1) }
        @objc private func handleScanForward(_ g: UILongPressGestureRecognizer) { scan(g, direction: 1) }

        private func scan(_ g: UILongPressGestureRecognizer, direction: Double) {
            switch g.state {
            case .began:
                isScanning = true
                parent.onScanBegan(direction)
            case .ended, .cancelled, .failed:
                endScanIfRunning()
            default:
                break
            }
        }
    }
}
