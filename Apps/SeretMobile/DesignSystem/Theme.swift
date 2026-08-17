import DebridUI
import SwiftUI

/// The mobile "Gold Glass" look.
///
/// The brand colours live once, in `DebridUI.SeretPalette`, so they cannot drift from tvOS.
/// `Palette` re-exposes them under the name every view already uses (`Theme.Palette.gold`), which
/// is why sharing them did not touch a single call site.
///
/// `Typo`, `Space`, `Radius` and `Motion` stay here: they are handheld values with nothing
/// meaningful in common with a ten-foot type ramp.
enum Theme {
    enum Palette {
        static let gold        = SeretPalette.gold
        static let goldLight   = SeretPalette.goldLight
        static let goldBright  = SeretPalette.goldBright
        static let goldDeep    = SeretPalette.goldDeep
        static let goldGlow    = SeretPalette.goldGlow
        static let canvas      = SeretPalette.canvas
        static let surface1    = SeretPalette.surface1
        static let surface2    = SeretPalette.surface2
        static let chipFill    = SeretPalette.chipFill
        static let textPrimary  = SeretPalette.textPrimary
        static let textTertiary = SeretPalette.textTertiary
        static let onGold       = SeretPalette.onGold
        static let destructive  = SeretPalette.destructive
        static let ratingGood   = SeretPalette.ratingGood
        static let ratingMid    = SeretPalette.ratingMid
        static let ratingBad    = SeretPalette.ratingBad

        static let goldGradient = SeretPalette.goldGradient
        static let markGradient = SeretPalette.markGradient

        static let trueBlack = Color.black

        // --- Deliberately NOT shared: these differ from tvOS on purpose. ---

        /// 0.09 here, 0.10 on tvOS.
        static let hairline = Color.white.opacity(0.09)
        /// Darker than the tvOS value: this sits in a three-step ramp with `textTertiary` below it,
        /// and is read at arm's length rather than across a room.
        static let textSecondary = Color(hex: 0x8A8A90)
        /// Faint top glow used as a screen background wash. The radius scales with the screen —
        /// 520 here against 1300 on a TV.
        static let canvasGlow = RadialGradient(
            colors: [Color(hex: 0xEBC11D, alpha: 0.14), .clear],
            center: .init(x: 0.8, y: -0.05), startRadius: 0, endRadius: 520)

        /// Maps a profile's `colorTag` to its avatar color; defaults to gold.
        static func color(for tag: String) -> Color { SeretPalette.color(for: tag) }
    }

    enum Typo {
        static func titleXL() -> Font { .system(size: 30, weight: .heavy) }
        static func title()   -> Font { .system(size: 22, weight: .bold) }
        static func headline() -> Font { .system(size: 17, weight: .semibold) }
        static func body()    -> Font { .system(size: 15, weight: .regular) }
        static func label()   -> Font { .system(size: 12, weight: .semibold) }
        static func caption() -> Font { .system(size: 12, weight: .medium).monospacedDigit() }
    }

    enum Space {
        static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12
        static let lg: CGFloat = 16, xl: CGFloat = 20, xxl: CGFloat = 24, xxxl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 12, chip: CGFloat = 8, pill: CGFloat = 22, sheet: CGFloat = 28
    }

    enum Motion {
        static let quick    = Animation.spring(response: 0.30, dampingFraction: 0.85)
        static let standard = Animation.spring(response: 0.45, dampingFraction: 0.82)
        static let hero     = Animation.spring(response: 0.60, dampingFraction: 0.80)
        static let fade     = Animation.easeInOut(duration: 0.25)
    }
}
