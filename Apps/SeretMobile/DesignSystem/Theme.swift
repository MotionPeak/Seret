import DebridUI
import SwiftUI

/// The mobile Liquid Glass look: a near-black navy canvas, white as the ONLY highlight colour, and
/// glass for every resting control (see `Glass.swift`).
///
/// The colour values are SeretTV's `Theme.Palette` copied, not shared, so the phone and the TV read
/// as one product while each app keeps its own tokens. The old warm brand tokens were removed
/// outright (not renamed) so the compiler found every use. Nothing here reads
/// `DebridUI.SeretPalette`'s brand colours any more.
///
/// `Typo`, `Space`, `Radius` and `Motion` are handheld values with nothing meaningful in common
/// with a ten-foot type ramp, so they stay here.
enum Theme {
    enum Palette {
        /// Page background.
        static let canvas   = Color(hex: 0x0A0D14)
        /// Placeholders and rows at rest.
        static let surface1 = Color(hex: 0x141925)
        static let surface2 = Color(hex: 0x1C2230)
        /// The iPad sidebar panel: `panelTop` → `panelBottom`, top to bottom.
        static let panelTop    = Color(hex: 0x181D2A, alpha: 0.97)
        static let panelBottom = Color(hex: 0x0A0D15, alpha: 0.97)
        /// Chips and small fills at rest — the flat stand-in for glass where real glass would be
        /// noise (a quality chip inside a list row).
        static let glass    = Color.white.opacity(0.17)
        /// A faint resting fill.
        static let glassFaint = Color.white.opacity(0.08)
        /// Dividers and resting outlines.
        static let hairline = Color.white.opacity(0.10)
        /// An outline that has to be seen: the current item in a strip, the in-file Hebrew seal.
        static let strokeStrong = Color.white.opacity(0.85)

        static let textPrimary   = Color(hex: 0xF5F6F8)
        static let textSecondary = Color(hex: 0xA3AAB8)
        static let textTertiary  = Color(hex: 0x6E7687)

        /// The accent: the selected pill, the primary action, progress and scrub fills.
        static let focus   = Color.white
        /// Text and icons drawn ON a `focus` fill.
        static let onFocus = Color(hex: 0x0B0F17)
        /// Laid over a poster to say "finished": a watched tile's dim.
        static let artDim = Color.black.opacity(0.45)
        /// The unfilled part of a progress line or the scrub bar, under a `focus` fill.
        static let track = Color.white.opacity(0.30)
        /// The disc behind a badge drawn on artwork (the watched ✓).
        static let badgeBacking = Color.black.opacity(0.55)
        /// The near-black a page's legibility shade fades from, over backdrop art.
        static let shadeInk = Color(hex: 0x080A11)

        /// A switch that is on. Not `focus`: a white track under the white knob reads as off.
        static let toggleOn = Color(hex: 0x34C759)

        /// Destructive intent (Remove, Disconnect, Sign Out).
        static let destructive = SeretPalette.destructive
        /// Critic-score bands — the chips keep their own colours.
        static let ratingGood  = SeretPalette.ratingGood
        static let ratingMid   = SeretPalette.ratingMid
        static let ratingBad   = SeretPalette.ratingBad
        /// The IMDb chip keeps IMDb's own yellow — a rating brand, not the app's accent.
        static let imdbYellow = Color(hex: 0xF5C518)

        static let trueBlack = Color.black

        /// The logo mark: white to a cool silver.
        static let silverGradient = LinearGradient(
            colors: [Color.white, Color(hex: 0xC9CEDA)],
            startPoint: .topLeading, endPoint: .bottomTrailing)

        /// A profile avatar with no colour of its own.
        static let avatarGradient = LinearGradient(
            colors: [Color(hex: 0x5B7CFA), Color(hex: 0x7B5CF0)],
            startPoint: .topLeading, endPoint: .bottomTrailing)

        /// The colour tag a new profile starts on.
        static let defaultColorTag = "indigo"

        /// Maps a profile's `colorTag` to its avatar colour; defaults to indigo. Same mapping as
        /// SeretTV, so a profile looks alike everywhere.
        static func color(for tag: String) -> Color {
            switch tag {
            case "blue":   return Color(hex: 0x3B82F6)
            case "green":  return Color(hex: 0x22C55E)
            case "red":    return destructive
            case "purple": return Color(hex: 0xA855F7)
            default:       return Color(hex: 0x6C6CF5)
            }
        }
    }

    enum Typo {
        static func titleXL() -> Font { .system(size: 30, weight: .heavy) }
        static func title()   -> Font { .system(size: 22, weight: .bold) }
        static func headline() -> Font { .system(size: 17, weight: .semibold) }
        static func body()    -> Font { .system(size: 15, weight: .regular) }
        static func label()   -> Font { .system(size: 12, weight: .semibold) }
        static func caption() -> Font { .system(size: 12, weight: .medium).monospacedDigit() }
        /// A root page's own title ("Seret", "Movies") beside its glass buttons.
        static func pageTitle() -> Font { .system(size: 30, weight: .heavy) }
        /// A rail's heading ("Continue Watching").
        static func railTitle() -> Font { .system(size: 20, weight: .bold) }
    }

    enum Space {
        static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12
        static let lg: CGFloat = 16, xl: CGFloat = 20, xxl: CGFloat = 24, xxxl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 12, chip: CGFloat = 8, pill: CGFloat = 22, sheet: CGFloat = 28
        /// The floating iPad sidebar panel.
        static let panel: CGFloat = 28
    }

    enum Motion {
        static let quick    = Animation.spring(response: 0.30, dampingFraction: 0.85)
        static let standard = Animation.spring(response: 0.45, dampingFraction: 0.82)
        static let hero     = Animation.spring(response: 0.60, dampingFraction: 0.80)
        static let fade     = Animation.easeInOut(duration: 0.25)
    }
}
