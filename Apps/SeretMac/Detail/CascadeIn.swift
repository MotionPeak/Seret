import SwiftUI

/// The title page's settle-in, once the hero flight has landed (or there was no flight at all):
/// each hero-copy child and page section fades up with a slight rise and blur, staggered by
/// `index`. Reduce Motion drops it to one flat cross-fade with no offset, no blur and no stagger.
struct CascadeIn: ViewModifier {
    let index: Int
    /// Whether the cascade may play at all right now — `false` keeps the content invisible
    /// (a forward flight still mid-air over this page's own hero band).
    var active: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: Bool { active }

    func body(content: Content) -> some View {
        if reduceMotion {
            content
                .opacity(shown ? 1 : 0)
                .animation(Theme.Motion.fade, value: shown)
        } else {
            content
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 14)
                .blur(radius: shown ? 0 : 5)
                .animation(Theme.Motion.standard.delay(shown ? Double(index) * 0.05 : 0), value: shown)
        }
    }
}

extension View {
    /// `index` staggers this view's own entrance by `index × 50 ms` behind the first. `active`
    /// gates the entrance itself — pass `shell.flight` state through it so a page under a still
    /// -landing flight stays hidden until `landFlight` fires.
    func cascadeIn(index: Int, active: Bool = true) -> some View {
        modifier(CascadeIn(index: index, active: active))
    }
}
