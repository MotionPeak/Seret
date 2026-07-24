import SwiftUI
import UIKit

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

    /// Explicitly non-focusable. This is load-bearing, not incidental — see the type doc.
    final class InputView: UIView {
        override var canBecomeFocused: Bool { false }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PlayerInputSurface
        private var recognizers: [UIGestureRecognizer] = []
        /// Horizontal displacement at which a drag stops being a stray thumb-rest and becomes a
        /// scrub. Low enough to feel immediate, high enough that a click doesn't scrub.
        private let scrubThreshold: CGFloat = 20
        private var isScrubbing = false

        init(parent: PlayerInputSurface) { self.parent = parent }

        func install(on view: UIView) {
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
            if !active, isScrubbing {
                isScrubbing = false
                parent.onScrubCancelled()
            }
        }

        // Every recognizer here is a different input channel — none should starve another.
        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        @objc private func handleWake(_ g: UILongPressGestureRecognizer) {
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
            let dx = g.translation(in: g.view).x
            switch g.state {
            case .changed:
                if !isScrubbing, abs(dx) >= scrubThreshold {
                    isScrubbing = true
                    parent.onScrubBegan()
                }
                if isScrubbing { parent.onScrubMoved(Double(dx)) }
            case .ended:
                if isScrubbing { isScrubbing = false; parent.onScrubEnded() }
            case .cancelled, .failed:
                if isScrubbing { isScrubbing = false; parent.onScrubCancelled() }
            default:
                break
            }
        }

        // A left/right tap nudges the scrub target while scrubbing and skips otherwise — the
        // caller decides which; it only needs the signed amount.
        @objc private func handleLeft()  { parent.onSkip(-10) }
        @objc private func handleRight() { parent.onSkip(10) }
        @objc private func handleUp()    { parent.onUp() }
        @objc private func handleDown()  { parent.onDown() }
        @objc private func handleSelect() {
            if isScrubbing { isScrubbing = false; parent.onScrubEnded() }   // click commits early
            else { parent.onSelect() }
        }

        @objc private func handleScanBack(_ g: UILongPressGestureRecognizer) { scan(g, direction: -1) }
        @objc private func handleScanForward(_ g: UILongPressGestureRecognizer) { scan(g, direction: 1) }

        private func scan(_ g: UILongPressGestureRecognizer, direction: Double) {
            switch g.state {
            case .began: parent.onScanBegan(direction)
            case .ended, .cancelled, .failed: parent.onScanEnded()
            default: break
            }
        }
    }
}
