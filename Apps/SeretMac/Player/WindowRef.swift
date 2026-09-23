import AppKit
import SwiftUI

/// The player screen's hosting `NSWindow`, held weakly so the reader never keeps the window alive.
/// `isFullScreen` is set from outside (`PlayerScreen` watches `NSWindow` full-screen notifications)
/// because `WindowReaderView` only learns the window at `viewDidMoveToWindow`, not on every
/// transition afterwards.
@MainActor
@Observable
final class WindowRef {
    @ObservationIgnored weak var window: NSWindow?
    private(set) var isFullScreen = false

    func setFullScreen(_ value: Bool) { isFullScreen = value }

    /// Undo the HUD's traffic-light fade. Called when the player screen disappears, so closing the
    /// player never leaves the window's close/minimise/zoom buttons invisible.
    func restoreChrome() { setTrafficLightsHidden(false) }

    func setTrafficLightsHidden(_ hidden: Bool) {
        guard let window else { return }
        let alpha: CGFloat = hidden ? 0 : 1
        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.alphaValue = alpha
        }
    }
}

/// Reads the hosting `NSWindow` into a `WindowRef` — an `NSViewRepresentable` with no content of
/// its own, just a hook into `viewDidMoveToWindow`.
struct WindowReader: NSViewRepresentable {
    let ref: WindowRef

    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.ref = ref
        return view
    }

    func updateNSView(_ view: WindowReaderView, context: Context) {
        view.ref = ref
    }
}

@MainActor
final class WindowReaderView: NSView {
    var ref: WindowRef?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        ref?.window = window
        ref?.setFullScreen(window?.styleMask.contains(.fullScreen) ?? false)
    }
}
