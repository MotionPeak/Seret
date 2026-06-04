import SwiftUI
import UIKit

/// The focusable scrub surface.
///
/// On tvOS the Siri-remote trackpad delivers its (indirect) touches to the **focused view's own**
/// gesture recognizers — not to passive overlays. So a continuous scrub needs the pan recognizer to
/// live on a view that is itself focusable *and* currently focused. (Earlier attempts put the pan on
/// a non-focusable overlay, so swipes never arrived and fell through to `onMoveCommand`'s ±10s steps;
/// removing those steps left no scrub at all.)
///
/// This representable hosts a focusable `UIView` with an indirect-touch `UIPanGestureRecognizer`; the
/// SwiftUI `ScrubBar` draws the visuals on top (non-interactive). A horizontal swipe enters scrub
/// mode and glides the preview; lifting commits the seek. Vertical movement is ignored so a dpad
/// click up can still move focus to the Subtitles button.
struct ScrubPad: UIViewRepresentable {
    let model: PlayerModel

    func makeUIView(context: Context) -> ScrubInteractionView {
        let view = ScrubInteractionView()
        view.model = model
        return view
    }

    func updateUIView(_ uiView: ScrubInteractionView, context: Context) {
        uiView.model = model
    }
}

@MainActor
final class ScrubInteractionView: UIView {
    weak var model: PlayerModel?

    /// Fraction of the whole timeline a full-width trackpad swipe traverses. >1 lets one swipe cover
    /// the entire clip (the owner wants fast full-clip scrubbing). Tune on a real Apple TV.
    private let sensitivity: Double = 1.5

    override var canBecomeFocused: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]  // Siri remote
        addGestureRecognizer(pan)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func didUpdateFocus(in context: UIFocusUpdateContext,
                                 with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        model?.setScrubberFocused(context.nextFocusedView === self)
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard let model else { return }
        switch pan.state {
        case .changed:
            let t = pan.translation(in: self)
            if !model.isScrubbing {
                guard abs(t.x) > abs(t.y), abs(t.x) > 8 else { return }  // horizontal only
                model.beginScrub()
            }
            pan.setTranslation(.zero, in: self)                          // pure incremental deltas
            let secondsPerPoint = model.duration / Double(max(1, bounds.width)) * sensitivity
            model.updateScrub(by: Double(t.x) * secondsPerPoint)
        case .ended:
            if model.isScrubbing { model.commitScrub() }                 // lift to seek
        case .cancelled, .failed:
            if model.isScrubbing { model.cancelScrub() }
        default:
            break
        }
    }
}
