import SwiftUI

/// One motion namespace for the whole tvOS app. Every animation pulls from here so the app's
/// "feel" is tunable in one place and never drifts between screens (the cause of the
/// "sometimes it jumps too fast" inconsistency). Add motion where there was none (content
/// reveals, crossfades) rather than speeding things up.
extension Theme {
    enum Anim {
        /// Focus lift on pills / tiles / buttons — quick but not instant.
        static let focus = Animation.easeOut(duration: 0.18)
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
