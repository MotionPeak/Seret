import SwiftUI

/// One motion namespace for the whole tvOS app. Every animation pulls from here so the app's
/// "feel" is tunable in one place and never drifts between screens (the cause of the
/// "sometimes it jumps too fast" inconsistency). Add motion where there was none (content
/// reveals, crossfades) rather than speeding things up.
extension Theme {
    enum Anim {
        /// Focus lift on posters / pills / buttons — a quick start with a long, soft settle.
        ///
        /// Route EVERY focus transition through this. Six sites used to hardcode their own 0.15,
        /// so focus moved at a different speed depending on which screen you were looking at —
        /// exactly the drift this namespace exists to prevent.
        static let focus = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24)
        /// Chrome that opens — the side menu growing from its capsule into the panel. Slower than
        /// focus on purpose: a panel opening is a bigger movement than a tile lifting.
        static let panelOpen = Animation.timingCurve(0.2, 0.9, 0.2, 1, duration: 0.46)
        /// The same chrome closing — quicker and accelerating away, so dismissing never drags.
        static let panelClose = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.34)
        /// The white selection pill sliding between rows.
        static let pill = Animation.timingCurve(0.2, 0.9, 0.2, 1, duration: 0.30)
        /// A browse page scrolling the newly focused rail up to the top of the rail area — the
        /// mockup's rows-track curve: unhurried, so the whole page glides rather than jumps.
        static let railScroll = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5)
        /// The page backdrop cross-fading to the newly focused title.
        static let backdrop = Animation.easeInOut(duration: 0.6)
        /// The focus preview's text leaving…
        static let previewOut = Animation.easeOut(duration: 0.18)
        /// …and the new text arriving (with an 8pt rise at the call site).
        static let previewIn = Animation.easeOut(duration: 0.25)
        /// Route crossfade — splash → shell, sign-in → shell.
        static let pageFade = Animation.easeInOut(duration: 0.30)
        /// The one "delightful" spring — hero & profile motion.
        static let heroSpring = Animation.spring(response: 0.40, dampingFraction: 0.80)
        /// AsyncImage crossfade from placeholder → loaded artwork.
        static let imageFade = Animation.easeOut(duration: 0.35)

        /// Transitional alias for the side menu's open/close. The side-menu rework replaces its
        /// last use with `panelOpen`/`panelClose`; do not add new ones.
        static let panel = panelOpen

        /// Focus scale for posters, cards and pills.
        static let focusScale: CGFloat = 1.08
        /// Focus scale for text buttons — a pill full of words reads as jumping at 1.08.
        static let buttonFocusScale: CGFloat = 1.04
        /// Slightly larger lift for hero-class focus targets (profile avatars).
        static let heroFocusScale: CGFloat = 1.10
    }
}
