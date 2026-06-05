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
    let onShowSettings: () -> Void

    func makeUIView(context: Context) -> ScrubInteractionView {
        let view = ScrubInteractionView()
        view.model = model
        view.onShowSettings = onShowSettings
        return view
    }

    func updateUIView(_ uiView: ScrubInteractionView, context: Context) {
        uiView.model = model
        uiView.onShowSettings = onShowSettings
    }
}

@MainActor
final class ScrubInteractionView: UIView {
    weak var model: PlayerModel?
    var onShowSettings: (() -> Void)?

    /// Fraction of the whole timeline a full-width trackpad swipe traverses.
    private let sensitivity: Double = 1.0
    /// Vertical distance (points) before a down swipe is treated as "show settings".
    private let pullThreshold: CGFloat = 60
    /// Direction the current pan committed to, if any.
    private enum Gesture { case horizontal, verticalDown }
    private var current: Gesture?
    private var pulledSettings = false

    override var canBecomeFocused: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]  // Siri remote
        addGestureRecognizer(pan)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    /// Click is play/pause. (On this remote every press arrives as .select, even side clicks.)
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let model, presses.contains(where: { $0.type == .select }) {
            model.togglePlayPause()
        } else {
            super.pressesBegan(presses, with: event)
        }
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
