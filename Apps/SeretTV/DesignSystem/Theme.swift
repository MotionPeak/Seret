import DebridUI
import SwiftUI

/// tvOS tokens — a near-black navy canvas with white as the ONLY highlight colour.
///
/// The Apple TV app no longer shares the brand palette with mobile and Mac: `DebridUI.SeretPalette`
/// keeps its warm brand colours for those apps, and this namespace owns every colour the TV draws. Focus,
/// selection and progress are white; resting controls are translucent white glass; there are no
/// glows. The old warm tokens were removed outright (not renamed) so the compiler found every use.
///
/// The type ramp (`Typography`), `Layout` and `Anim` stay here too: they are tuned for a ten-foot
/// viewing distance and have nothing meaningful in common with the handheld values.
enum Theme {
    enum Palette {
        /// Page background.
        static let canvas   = Color(hex: 0x0A0D14)
        /// Placeholders and rows at rest.
        static let surface1 = Color(hex: 0x141925)
        static let surface2 = Color(hex: 0x1C2230)
        /// The side menu panel and side sheets: `panelTop` → `panelBottom`, top to bottom.
        static let panelTop    = Color(hex: 0x181D2A, alpha: 0.97)
        static let panelBottom = Color(hex: 0x0A0D15, alpha: 0.97)
        /// Circular buttons and chips at rest.
        static let glass    = Color.white.opacity(0.17)
        /// Dividers and resting outlines.
        static let hairline = Color.white.opacity(0.10)
        /// An outline that has to be seen: the current item in a strip, a focused text block, the
        /// in-file Hebrew seal.
        static let strokeStrong = Color.white.opacity(0.85)

        static let textPrimary   = Color(hex: 0xF5F6F8)
        static let textSecondary = Color(hex: 0xA3AAB8)
        static let textTertiary  = Color(hex: 0x6E7687)

        /// The accent: focus outlines, the selected pill, progress and scrub fills.
        static let focus   = Color.white
        /// Text and icons drawn ON a `focus` fill.
        static let onFocus = Color(hex: 0x0B0F17)
        /// The wash behind an open side menu.
        static let scrim   = Color(hex: 0x04070E, alpha: 0.66)

        /// Destructive intent (Remove, Disconnect, Sign Out).
        static let destructive = SeretPalette.destructive
        /// Critic-score bands — the chips keep their own colours.
        static let ratingGood  = SeretPalette.ratingGood
        static let ratingMid   = SeretPalette.ratingMid
        static let ratingBad   = SeretPalette.ratingBad

        /// The logo mark: white to a cool silver.
        static let silverGradient = LinearGradient(
            colors: [Color.white, Color(hex: 0xC9CEDA)],
            startPoint: .topLeading, endPoint: .bottomTrailing)

        /// A profile avatar with no colour of its own.
        static let avatarGradient = LinearGradient(
            colors: [Color(hex: 0x5B7CFA), Color(hex: 0x7B5CF0)],
            startPoint: .topLeading, endPoint: .bottomTrailing)

        /// The colour tag a new profile starts on. A tag `color(for:)` does not know — including
        /// the warm one older profiles were created with — draws as the default indigo.
        static let defaultColorTag = "indigo"

        /// An avatar circle's fill: the named colour when the tag has one, the indigo gradient
        /// otherwise.
        static func avatarFill(for tag: String) -> AnyShapeStyle {
            switch tag {
            case "blue", "green", "red", "purple": AnyShapeStyle(color(for: tag))
            default:                               AnyShapeStyle(avatarGradient)
            }
        }

        /// Maps a profile's `colorTag` to its avatar colour; defaults to indigo.
        ///
        /// Deliberately not `SeretPalette.color(for:)`, whose default is the mobile brand colour
        /// the TV no longer draws. The named colours match it so a profile looks alike everywhere.
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
}

/// The full-screen canvas behind screen content: flat navy, no wash.
struct CanvasBackground: View {
    var body: some View {
        Theme.Palette.canvas.ignoresSafeArea()
    }
}
