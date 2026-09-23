import AppKit
import SwiftUI

/// Moves the window's close / minimise / zoom buttons inside the floating sidebar's top-left corner
/// (approved mockup 2). With a hidden title bar AppKit pins them to the window's own corner, which is
/// exactly where the sidebar's rounded corner floats, so they sat on its edge.
///
/// AppKit lays the buttons out again whenever the title bar does (resize, full screen, key changes),
/// so the offset is re-applied after each of those. Removing the view hands the layout back to AppKit.
struct TrafficLightsPlacement: NSViewRepresentable {
    /// Where the close button's top-left corner goes, measured from the window's top-left.
    let origin: CGPoint

    func makeNSView(context: Context) -> TrafficLightsAnchor { TrafficLightsAnchor(origin: origin) }

    func updateNSView(_ view: TrafficLightsAnchor, context: Context) {
        view.origin = origin
        view.apply()
    }
}

/// The pure part: where each button goes, in its title-bar superview's (bottom-up) coordinates.
enum TrafficLightsLayout {
    /// Shifts every button by the same amount, so AppKit's own spacing between them is kept.
    static func frames(for current: [CGRect], containerHeight: CGFloat, origin: CGPoint) -> [CGRect] {
        guard let close = current.first else { return [] }
        let dx = origin.x - close.minX
        let dy = (containerHeight - origin.y - close.height) - close.minY
        return current.map { $0.offsetBy(dx: dx, dy: dy) }
    }
}

final class TrafficLightsAnchor: NSView {
    var origin: CGPoint
    private var observers: [NSObjectProtocol] = []

    init(origin: CGPoint) {
        self.origin = origin
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("TrafficLightsAnchor is created in code") }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        // Leaving: give the buttons back to AppKit's layout (the sign-in screen has no sidebar).
        if newWindow == nil { window?.standardWindowButton(.closeButton)?.superview?.needsLayout = true }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                                          NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification,
                                          NSWindow.didResignKeyNotification, NSWindow.didBecomeMainNotification]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            }
        }
        apply()
        // The title bar finishes its first layout after this view joins the window.
        DispatchQueue.main.async { [weak self] in self?.apply() }
    }

    func apply() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
        guard let container = buttons.first?.superview else { return }
        let frames = TrafficLightsLayout.frames(for: buttons.map(\.frame),
                                                containerHeight: container.bounds.height, origin: origin)
        for (button, frame) in zip(buttons, frames) where button.frame != frame { button.setFrameOrigin(frame.origin) }
    }
}
