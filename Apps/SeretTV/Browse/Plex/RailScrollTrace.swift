#if DEBUG
import UIKit
import ObjectiveC

/// DEBUG `-railScrollTrace`: prints every change to a browse page's rail-area scroll offset (the
/// vertical scroll view whose top inset is the hidden band), the focused item's frame on screen,
/// and — for the first few small moves — the stack that made them. This is how the rail "pop" was
/// pinned on `_UIFocusDisplayLinkScrollAnimator`: tvOS's focus scroller wanting the focused poster
/// at ~551pt, the page wanting it lower. Run it again if rows start to drift or bounce.
enum RailScrollTrace {
    static func install() {
        guard ProcessInfo.processInfo.arguments.contains("-railScrollTrace") else { return }
        let cls: AnyClass = UIScrollView.self
        for name in ["setContentOffset:", "setContentOffset:animated:"] {
            let sel = NSSelectorFromString(name)
            guard let m = class_getInstanceMethod(cls, sel) else { continue }
            if name == "setContentOffset:" {
                typealias F = @convention(c) (UIScrollView, Selector, CGPoint) -> Void
                let orig = unsafeBitCast(method_getImplementation(m), to: F.self)
                let block: @convention(block) (UIScrollView, CGPoint) -> Void = { sv, p in
                    // UIKit sets a scroll view's offset on the main thread only.
                    MainActor.assumeIsolated { report(sv, p, name) }
                    orig(sv, sel, p)
                }
                method_setImplementation(m, imp_implementationWithBlock(block))
            } else {
                typealias F = @convention(c) (UIScrollView, Selector, CGPoint, Bool) -> Void
                let orig = unsafeBitCast(method_getImplementation(m), to: F.self)
                let block: @convention(block) (UIScrollView, CGPoint, Bool) -> Void = { sv, p, a in
                    MainActor.assumeIsolated { report(sv, p, name + (a ? " ANIM" : "")) }
                    orig(sv, sel, p, a)
                }
                method_setImplementation(m, imp_implementationWithBlock(block))
            }
        }
    }

    @MainActor static var printed = 0
    @MainActor static func report(_ sv: UIScrollView, _ p: CGPoint, _ how: String) {
        // The rail area: a vertical scroll view whose top inset is the hidden band (924).
        guard sv.contentInset.top > 800 || sv.adjustedContentInset.top > 800 else { return }
        let dy = p.y - sv.contentOffset.y
        guard abs(dy) > 0.5 else { return }
        print("[RAILTRACE] SET \(how) \(Int(sv.contentOffset.y))→\(Int(p.y)) dy=\(Int(dy)) inset=\(sv.adjustedContentInset) bounds=\(sv.bounds.size) frameInWin=\(sv.convert(sv.bounds, to: nil).integral)")
        if let item = sv.window?.windowScene?.focusSystem?.focusedItem {
            let f = item.frame
            let space = item.parentFocusEnvironment?.focusItemContainer?.coordinateSpace ?? UIScreen.main.coordinateSpace; let win = space.convert(f, to: UIScreen.main.coordinateSpace)
            print("[RAILTRACE] FOCUSED \(type(of: item)) frameOnScreen=\(win.integral)")
        }
        if abs(dy) >= 4 && abs(dy) <= 80 && printed < 6 {
            printed += 1
            let frames = Thread.callStackSymbols.prefix(28).map { "    " + $0 }.joined(separator: "\n")
            print("[RAILTRACE] STACK\n\(frames)")
        }
    }
}
#endif
