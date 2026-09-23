import AppKit
import Testing
@testable import Seret

/// VLCKit 4 renders by adding its own Metal view as a subview of the drawable and sizing it from the
/// drawable's bounds once, before SwiftUI has laid anything out. These pin the fix the iOS/tvOS
/// drawable already carries: every subview is forced to fill the drawable, on add and on layout.
@MainActor
@Suite struct VLCDrawableViewTests {
    @Test func anAddedSubviewIsSizedToTheDrawable() {
        let drawable = VLCDrawableView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        let render = NSView(frame: .zero)
        drawable.addSubview(render)
        #expect(render.frame == drawable.bounds)
    }

    @Test func layoutPullsAMisSizedSubviewBackToTheBounds() {
        let drawable = VLCDrawableView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        let render = NSView(frame: .zero)
        drawable.addSubview(render)
        drawable.setFrameSize(NSSize(width: 1280, height: 720))
        render.frame = NSRect(x: 5, y: 5, width: 10, height: 10)     // what VLCKit would leave
        drawable.layout()
        #expect(render.frame == drawable.bounds)
    }

    @Test func theDrawableIsBlackBeforeVLCRendersAFrame() {
        let drawable = VLCDrawableView(frame: .zero)
        #expect(drawable.layer?.backgroundColor == NSColor.black.cgColor)
    }
}
