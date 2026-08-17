import DebridUI
import SwiftUI

/// tvOS "Gold Glass" tokens.
///
/// The brand colours live once, in `DebridUI.SeretPalette`, so they cannot drift between the two
/// apps. `Palette` re-exposes them under the name every view already uses (`Theme.Palette.gold`),
/// which is why sharing them did not touch a single call site.
///
/// The type ramp (`Typography`), `Layout` and `Anim` stay here on purpose: they are tuned for a
/// ten-foot viewing distance and have nothing meaningful in common with the handheld values.
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
        static let textPrimary = SeretPalette.textPrimary
        static let destructive = SeretPalette.destructive
        static let scrim       = SeretPalette.scrim
        static let ratingGood  = SeretPalette.ratingGood
        static let ratingMid   = SeretPalette.ratingMid
        static let ratingBad   = SeretPalette.ratingBad

        static let goldGradient = SeretPalette.goldGradient
        static let markGradient = SeretPalette.markGradient

        // --- Deliberately NOT shared: these differ from mobile on purpose. ---

        /// 0.10 here, 0.09 on mobile.
        static let hairline = Color.white.opacity(0.10)
        /// Lighter than mobile's, which sits in a three-step ramp; this one has to read across a
        /// room.
        static let textSecondary = Color(hex: 0x9A9AA0)
        /// The radius scales with the screen — 1300 on a TV against mobile's 520.
        static let canvasGlow = RadialGradient(
            colors: [Color(hex: 0xEBC11D, alpha: 0.16), .clear],
            center: .init(x: 0.85, y: -0.1), startRadius: 0, endRadius: 1300)

        /// Maps a profile's `colorTag` to its avatar color; defaults to gold.
        static func color(for tag: String) -> Color { SeretPalette.color(for: tag) }
    }
}

/// Full-screen Gold Glass canvas wash (black + faint gold glow). Behind screen content.
struct CanvasBackground: View {
    var body: some View {
        ZStack {
            Theme.Palette.canvas
            Theme.Palette.canvasGlow
        }
        .ignoresSafeArea()
    }
}
