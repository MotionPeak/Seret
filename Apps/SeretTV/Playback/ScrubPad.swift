import SwiftUI
import UIKit

/// A transparent overlay that turns Siri-remote trackpad swipes into a continuous scrub gesture.
///
/// SwiftUI's `onMoveCommand` only reports discrete dpad *clicks* (which the scrubber uses for ±10s);
/// gliding fast across the timeline needs a real `UIPanGestureRecognizer` on the touch surface.
/// Active only while in scrub mode (`isActive` = `model.isScrubbing`, entered by a select press):
/// a pan glides the preview marker; the seek is committed by a second select press, not on lift
/// (so the user can keep swiping to reach anywhere). `cancelScrub`/`commitScrub` are driven by the
/// view (Menu / select / play-pause), not by the gesture ending.
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
                let translation = pan.translation(in: view)
                pan.setTranslation(.zero, in: view)   // accumulate pure incremental deltas
                let secondsPerPoint = model.duration / Double(max(1, view.bounds.width)) * sensitivity
                model.updateScrub(by: Double(translation.x) * secondsPerPoint)
            default:
                break   // entering/committing/cancelling scrub is an explicit select/Menu press
            }
        }
    }
}
