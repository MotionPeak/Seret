import SwiftUI
import DebridUI
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
/// SwiftUI `ScrubBar` draws the visuals on top (non-interactive). A **click (select press) engages
/// scrub mode** — only then does a swipe glide the preview (so merely resting a finger on the
/// trackpad while focused doesn't scrub). A second click commits the seek; Menu cancels.
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

    /// Fraction of the whole timeline a full-width trackpad swipe traverses. Tune on a real Apple TV.
    private let sensitivity: Double = 1.0

    override var canBecomeFocused: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]  // Siri remote
        addGestureRecognizer(pan)
        // Left/right clicks → ±10s. The focus engine swallows arrow presses before they reach
        // pressesBegan, so catch them with press-typed tap recognizers instead.
        let back = UITapGestureRecognizer(target: self, action: #selector(skipBackward))
        back.allowedPressTypes = [NSNumber(value: UIPress.PressType.leftArrow.rawValue)]
        addGestureRecognizer(back)
        let forward = UITapGestureRecognizer(target: self, action: #selector(skipForward))
        forward.allowedPressTypes = [NSNumber(value: UIPress.PressType.rightArrow.rawValue)]
        addGestureRecognizer(forward)
    }

    @objc private func skipForward() {
        guard let model else { return }
        if model.isScrubbing { model.updateScrub(by: 10) } else { model.skip(10) }
    }
    @objc private func skipBackward() {
        guard let model else { return }
        if model.isScrubbing { model.updateScrub(by: -10) } else { model.skip(-10) }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func didUpdateFocus(in context: UIFocusUpdateContext,
                                 with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        model?.setScrubberFocused(context.nextFocusedView === self)
    }

    /// Center click toggles scrub mode: first click engages it, second click commits the seek.
    /// (±10s on left/right is handled by the press-typed tap recognizers set up in init.)
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let model, presses.contains(where: { $0.type == .select }) {
            if model.isScrubbing { model.commitScrub() } else { model.beginScrub() }
        } else {
            super.pressesBegan(presses, with: event)   // Up/Down focus moves, Menu, Play/Pause
        }
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        // Only scrub once a click has engaged scrub mode — never on a bare hover/swipe.
        guard let model, model.isScrubbing, pan.state == .changed else { return }
        let t = pan.translation(in: self)
        pan.setTranslation(.zero, in: self)                              // pure incremental deltas
        let secondsPerPoint = model.duration / Double(max(1, bounds.width)) * sensitivity
        model.updateScrub(by: Double(t.x) * secondsPerPoint)
    }
}
