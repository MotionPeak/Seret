import SwiftUI
import DebridUI
import UIKit

/// The invisible focusable surface that owns ALL the player's gestures. On tvOS, indirect-touch
/// gestures reach only the focused view, so this is the focused view by default. It receives:
///   • horizontal swipe → scrub mode (auto-engages once horizontal distance exceeds the threshold)
///   • vertical-DOWN swipe from anywhere → reveal the settings panel (top-down)
///   • center click (.select) → play / pause
struct ScrubPad: UIViewRepresentable {
    let model: PlayerModel
    let isInteractive: Bool      // false while SettingsPanel is open → ScrubPad ignores all input
    let onShowSettings: () -> Void

    func makeUIView(context: Context) -> ScrubInteractionView {
        let view = ScrubInteractionView()
        view.model = model
        view.onShowSettings = onShowSettings
        view.isInteractive = isInteractive
        return view
    }

    func updateUIView(_ uiView: ScrubInteractionView, context: Context) {
        uiView.model = model
        uiView.onShowSettings = onShowSettings
        uiView.isInteractive = isInteractive
    }
}

@MainActor
final class ScrubInteractionView: UIView {
    weak var model: PlayerModel?
    var onShowSettings: (() -> Void)?
    var isInteractive: Bool = true {
        didSet {
            if oldValue != isInteractive {
                pan.isEnabled = isInteractive
                setNeedsFocusUpdate()
            }
        }
    }

    /// Fraction of the whole timeline a full-width trackpad swipe traverses. Lower = slower,
    /// easier to swipe precisely.
    private let sensitivity: Double = 0.15
    /// Vertical distance (points) before a down swipe is treated as "show settings".
    private let pullThreshold: CGFloat = 60
    /// Direction the current pan committed to, if any.
    private enum Gesture { case horizontal, verticalDown }
    private var current: Gesture?
    private var pulledSettings = false
    private let pan = UIPanGestureRecognizer()

    override var canBecomeFocused: Bool { isInteractive }

    /// Last reported touch X on the remote's trackpad (in this view's coords). Used to decide
    /// whether a center `.select` click came from the LEFT, CENTER, or RIGHT third of the pad.
    private var lastTouchX: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        pan.addTarget(self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]  // Siri remote
        addGestureRecognizer(pan)
        // Older remotes' side-clicks fire .leftArrow / .rightArrow presses directly. Catch those too.
        let back = UITapGestureRecognizer(target: self, action: #selector(skipBackward))
        back.allowedPressTypes = [NSNumber(value: UIPress.PressType.leftArrow.rawValue)]
        addGestureRecognizer(back)
        let fwd  = UITapGestureRecognizer(target: self, action: #selector(skipForward))
        fwd.allowedPressTypes = [NSNumber(value: UIPress.PressType.rightArrow.rawValue)]
        addGestureRecognizer(fwd)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    // Track touch location so a center .select click can be routed by which third of the pad
    // the finger was on (this is how the native player does ±10s on remotes that send only .select).
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if let t = touches.first(where: { $0.type == .indirect }) { lastTouchX = t.location(in: self).x }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        if let t = touches.first(where: { $0.type == .indirect }) { lastTouchX = t.location(in: self).x }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        // keep `lastTouchX` so a click immediately after lift still routes correctly
    }

    /// A center `.select` press: route by trackpad-third (left = -10s, right = +10s, center = play/pause).
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard isInteractive, let model, presses.contains(where: { $0.type == .select }) else {
            super.pressesBegan(presses, with: event); return
        }
        let leftEdge  = bounds.width * 0.30
        let rightEdge = bounds.width * 0.70
        if let x = lastTouchX, x < leftEdge {
            model.skip(-10)
        } else if let x = lastTouchX, x > rightEdge {
            model.skip(10)
        } else {
            model.togglePlayPause()
        }
        model.revealScrubBar()
    }

    @objc private func skipBackward() {
        guard isInteractive, let model else { return }
        model.skip(-10); model.revealScrubBar()
    }
    @objc private func skipForward() {
        guard isInteractive, let model else { return }
        model.skip(10); model.revealScrubBar()
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard let model else { return }
        switch pan.state {
        case .began:
            current = nil
            pulledSettings = false
        case .changed:
            let t = pan.translation(in: self)
            // Commit to a direction on first meaningful movement.
            if current == nil {
                if abs(t.x) > abs(t.y), abs(t.x) > 8 {
                    current = .horizontal
                    model.beginScrub()
                } else if t.y > 8, abs(t.y) > abs(t.x) {
                    current = .verticalDown
                }
            }
            switch current {
            case .horizontal:
                pan.setTranslation(.zero, in: self)
                let secondsPerPoint = model.duration / Double(max(1, bounds.width)) * sensitivity
                model.updateScrub(by: Double(t.x) * secondsPerPoint)
            case .verticalDown:
                if !pulledSettings, t.y > pullThreshold {
                    pulledSettings = true
                    onShowSettings?()        // fires once per gesture
                }
            case nil:
                break
            }
        case .ended:
            if current == .horizontal, model.isScrubbing { model.commitScrub() }
            current = nil
        case .cancelled, .failed:
            if current == .horizontal, model.isScrubbing { model.cancelScrub() }
            current = nil
        default:
            break
        }
    }
}
