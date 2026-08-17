import SwiftUI

/// One motion namespace for the whole tvOS app. Every animation pulls from here so the app's
/// "feel" is tunable in one place and never drifts between screens (the cause of the
/// "sometimes it jumps too fast" inconsistency). Add motion where there was none (content
/// reveals, crossfades) rather than speeding things up.
extension Theme {
    enum Anim {
        /// Focus lift on pills / tiles / buttons — quick but not instant.
        ///
        /// Route EVERY focus transition through this. Six sites used to hardcode their own 0.15,
        /// so focus moved at a different speed depending on which screen you were looking at —
        /// exactly the drift this namespace exists to prevent.
        static let focus = Animation.easeOut(duration: 0.18)
        /// Chrome that opens or reveals — the side menu expanding, its scrim fading in. Slower than
        /// focus on purpose: a panel sliding is a bigger movement than a tile lifting.
        static let panel = Animation.easeOut(duration: 0.22)
        /// Route crossfade — splash → shell, sign-in → shell.
        static let pageFade = Animation.easeInOut(duration: 0.30)
        /// The one "delightful" spring — hero & profile motion.
        static let heroSpring = Animation.spring(response: 0.40, dampingFraction: 0.80)
        /// AsyncImage crossfade from placeholder → loaded artwork.
        static let imageFade = Animation.easeOut(duration: 0.35)

        /// Standard focus scale for in-content pills / tiles.
        static let focusScale: CGFloat = 1.06
        /// Slightly larger lift for hero-class focus targets.
        static let heroFocusScale: CGFloat = 1.10
    }
}
