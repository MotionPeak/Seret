import SwiftUI
import UIKit

/// A transparent overlay that turns Siri-remote trackpad swipes into a continuous scrub gesture.
///
/// Continuous swipe-scrub on the Siri remote trackpad. SwiftUI's `onMoveCommand` only reports
/// discrete dpad *clicks* (which jump in fixed steps); a fast glide across the whole timeline needs
/// a real `UIPanGestureRecognizer`. **Crucially the recognizer must opt into `.indirect` touches —
/// the remote trackpad delivers indirect touches, and without this the pan never fires and the
/// swipe falls through to `onMoveCommand` (the ±10s "stepping" the owner saw).**
///
/// Active whenever the scrubber holds focus (`isActive`). A horizontal swipe enters scrub mode and
/// glides the preview marker; lifting commits the seek. Vertical swipes are ignored so focus can
/// still move up to the Subtitles button.
///
/// `sensitivity` is the one tuning knob and is owner-on-device territory — the Siri remote's pan
/// translation scale isn't reproducible in the simulator.
struct ScrubPad: UIViewRepresentable {
    let model: PlayerModel
    let isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]  // Siri remote
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.model = model
        context.coordinator.isActive = isActive
    }

    @MainActor
    final class Coordinator: NSObject {
        var model: PlayerModel
        var isActive: Bool = false
        /// Fraction of the whole timeline a full-width trackpad swipe traverses. >1 means one swipe
        /// can cover the entire clip (the owner wants fast full-clip scrubbing). Tune on a real Apple TV.
        private let sensitivity: Double = 1.5

        init(model: PlayerModel) { self.model = model }

        @objc func handlePan(_ pan: UIPanGestureRecognizer) {
            guard isActive, let view = pan.view else { return }
            switch pan.state {
            case .changed:
                let t = pan.translation(in: view)
                if !model.isScrubbing {
                    guard abs(t.x) > abs(t.y), abs(t.x) > 8 else { return }  // horizontal only
                    model.beginScrub()
                    model.showControls()
                }
                pan.setTranslation(.zero, in: view)   // accumulate pure incremental deltas
                let secondsPerPoint = model.duration / Double(max(1, view.bounds.width)) * sensitivity
                model.updateScrub(by: Double(t.x) * secondsPerPoint)
            case .ended:
                if model.isScrubbing { model.commitScrub() }   // lift to seek
            case .cancelled, .failed:
                if model.isScrubbing { model.cancelScrub() }
            default:
                break
            }
        }
    }
}
