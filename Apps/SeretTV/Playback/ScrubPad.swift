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
    let isInteractive: Bool      // false while a panel is open → ScrubPad ignores all input
    let onShowSettings: () -> Void
    let onPullUp: () -> Void     // swipe up → reveal scrub bar (+ episode strip for shows)

    func makeUIView(context: Context) -> ScrubInteractionView {
        let view = ScrubInteractionView()
        view.model = model
        view.onShowSettings = onShowSettings
        view.onPullUp = onPullUp
        view.isInteractive = isInteractive
        return view
    }

    func updateUIView(_ uiView: ScrubInteractionView, context: Context) {
        uiView.model = model
        uiView.onShowSettings = onShowSettings
        uiView.onPullUp = onPullUp
        uiView.isInteractive = isInteractive
    }
}

@MainActor
final class ScrubInteractionView: UIView {
    weak var model: PlayerModel?
    var onShowSettings: (() -> Void)?
    var onPullUp: (() -> Void)?
    var isInteractive: Bool = true {
        didSet {
            guard oldValue != isInteractive else { return }
            pan.isEnabled = isInteractive
            // When the panel opens we become non-focusable, but UIKit won't move focus off us on
            // its own — and firing the focus update synchronously here happens before SwiftUI has
            // inserted the SettingsPanel into the focus hierarchy, so focus strands on this dead
            // pad (the "can't navigate the settings" bug). Defer one run-loop tick so the panel is
            // present, then hand focus to it.
            DispatchQueue.main.async { [weak self] in
                self?.setNeedsFocusUpdate()
                self?.updateFocusIfNeeded()
            }
        }
    }

    /// Fraction of the whole timeline a full-width trackpad swipe traverses. Lower = slower,
    /// easier to swipe precisely.
    private let sensitivity: Double = 0.15
    /// Vertical distance (points) before a vertical swipe is treated as a pull (settings / scrub).
    private let pullThreshold: CGFloat = 60
    /// Direction the current pan committed to, if any.
    private enum Gesture { case horizontal, verticalDown, verticalUp }
    private var current: Gesture?
    private var pulledUp = false
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
        // Side-clicks (.leftArrow / .rightArrow) are handled directly in `pressesBegan` — a press-type
        // UITapGestureRecognizer gets starved by the focus engine on 2nd-gen remotes, which is why the
        // old recognizer path did nothing. The responder-chain press path is reliable (same path the
        // center `.select` click already used successfully).
        // D-pad UP / DOWN clicks — a discrete affordance for the same pull-up (reveal bar) and
        // pull-down (episodes for a show, else settings) the trackpad swipe does, so the episode
        // strip isn't hidden behind a swipe-only gesture.
        let up = UITapGestureRecognizer(target: self, action: #selector(pressUp))
        up.allowedPressTypes = [NSNumber(value: UIPress.PressType.upArrow.rawValue)]
        addGestureRecognizer(up)
        let down = UITapGestureRecognizer(target: self, action: #selector(pressDown))
        down.allowedPressTypes = [NSNumber(value: UIPress.PressType.downArrow.rawValue)]
        addGestureRecognizer(down)
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

    /// All remote clicks route here (the reliable path — press-type gesture recognizers get starved by
    /// the focus engine). Left/right clickpad clicks skip ±10s directly; a center `.select` is routed
    /// by which third of the trackpad the thumb rested on.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard isInteractive, let model else { super.pressesBegan(presses, with: event); return }
        var handled = false
        for press in presses {
            switch press.type {
            case .leftArrow:
                model.skip(-10); handled = true
            case .rightArrow:
                model.skip(10); handled = true
            case .select:
                switch RemoteSkipZone.classify(touchX: lastTouchX.map(Double.init), width: Double(bounds.width)) {
                case .back:      model.skip(-10)
                case .forward:   model.skip(10)
                case .playPause: model.togglePlayPause()
                }
                handled = true
            default:
                break
            }
        }
        if handled { model.revealScrubBar() }
        else { super.pressesBegan(presses, with: event) }
    }

    @objc private func pressUp() {
        guard isInteractive else { return }
        onPullUp?()              // reveal the scrub bar (+ episode peek for shows)
    }
    @objc private func pressDown() {
        guard isInteractive else { return }
        onShowSettings?()        // episodes (a show, bar up) or the settings panel
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard let model else { return }
        switch pan.state {
        case .began:
            current = nil
            pulledSettings = false
            pulledUp = false
        case .changed:
            let t = pan.translation(in: self)
            // Commit to a direction on first meaningful movement.
            if current == nil {
                if abs(t.x) > abs(t.y), abs(t.x) > 8 {
                    current = .horizontal
                    model.beginScrub()
                } else if t.y > 8, abs(t.y) > abs(t.x) {
                    current = .verticalDown
                } else if t.y < -8, abs(t.y) > abs(t.x) {
                    current = .verticalUp
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
            case .verticalUp:
                if !pulledUp, -t.y > pullThreshold {
                    pulledUp = true
                    onPullUp?()              // fires once per gesture
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
