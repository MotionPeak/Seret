import DebridUI
import SwiftUI

/// The Mac's Gold Glass. Brand colours come from `DebridUI.SeretPalette`, so they cannot drift from
/// the TV and the phone; type, spacing, radii and motion are Mac values (read at desk distance, with a
/// pointer).
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
        static let trueBlack    = Color.black

        /// The iPhone values: the Mac is read at arm's length, not across a room.
        static let hairline      = Color.white.opacity(0.09)
        static let textSecondary = Color(hex: 0x8A8A90)
        /// Faint top-right glow behind every screen. Larger than the phone's: Mac windows are wide.
        static let canvasGlow = RadialGradient(
            colors: [Color(hex: 0xEBC11D, alpha: 0.14), .clear],
            center: .init(x: 0.8, y: -0.05), startRadius: 0, endRadius: 900)

        static func color(for tag: String) -> Color { SeretPalette.color(for: tag) }
    }

    enum Typo {
        static func titleXL()  -> Font { .system(size: 30, weight: .heavy) }
        static func title()    -> Font { .system(size: 22, weight: .bold) }
        static func headline() -> Font { .system(size: 15, weight: .semibold) }
        static func body()     -> Font { .system(size: 13, weight: .regular) }
        static func label()    -> Font { .system(size: 11, weight: .semibold) }
        static func caption()  -> Font { .system(size: 11, weight: .medium).monospacedDigit() }
    }

    enum Space {
        static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12
        static let lg: CGFloat = 16, xl: CGFloat = 20, xxl: CGFloat = 24, xxxl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 12, chip: CGFloat = 8, panel: CGFloat = 18, sidebar: CGFloat = 11
    }

    enum Motion {
        static let quick    = Animation.spring(response: 0.30, dampingFraction: 0.85)
        static let standard = Animation.spring(response: 0.45, dampingFraction: 0.82)
        static let hero     = Animation.spring(response: 0.60, dampingFraction: 0.80)
        /// The poster → page flight.
        static let flight   = Animation.spring(response: 0.62, dampingFraction: 0.84)
        /// Small celebratory bounces (stars, bookmarks).
        static let pop      = Animation.spring(response: 0.45, dampingFraction: 0.55)
        static let fade     = Animation.easeInOut(duration: 0.25)
    }
}
