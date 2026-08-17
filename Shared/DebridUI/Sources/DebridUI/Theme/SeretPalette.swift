import SwiftUI

public extension Color {
    /// `Color(hex: 0xEBC11D)` — the one place a colour is built from a literal.
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// The Gold Glass brand colours, shared by SeretTV and SeretMobile.
///
/// Both apps used to carry their own full copy of the palette, so the brand existed twice and could
/// drift silently — and a few tokens (the text colour on a gold fill, the critic-score bands) were
/// not in either copy at all, just repeated as raw hex at their call sites.
///
/// Only genuinely *identical* values live here. Three tokens legitimately differ per platform and
/// stay with their app:
///   - `hairline` — 0.10 on tvOS, 0.09 on mobile
///   - `textSecondary` — tvOS reads at ten feet; mobile has a three-step ramp with a tertiary below
///   - `canvasGlow` — the radius scales with the screen (1300 on a TV, 520 in the hand)
///
/// Those were left alone deliberately: unifying them changes how one of the apps looks, which is a
/// decision to make on purpose rather than as a side effect of sharing the file.
public enum SeretPalette {
    public static let gold       = Color(hex: 0xEBC11D)
    public static let goldLight  = Color(hex: 0xF6D24A)
    public static let goldBright = Color(hex: 0xFDE98A)
    public static let goldDeep   = Color(hex: 0xC8930A)
    public static let goldGlow   = Color(hex: 0xEBC11D, alpha: 0.40)

    public static let canvas   = Color(hex: 0x08080A)
    public static let surface1 = Color(hex: 0x141416)
    public static let surface2 = Color(hex: 0x1C1C1F)
    public static let chipFill = Color.white.opacity(0.12)

    public static let textPrimary = Color(hex: 0xF5F5F7)
    /// The dimmest step of the text ramp. Only mobile uses it today.
    public static let textTertiary = Color(hex: 0x5A5A60)

    /// Text drawn ON a gold fill. Not pure black — a very dark warm brown reads better on gold.
    /// Mobile repeated this as `Color(hex: 0x1A1400)` in seven places; tvOS uses `.black`.
    public static let onGold = Color(hex: 0x1A1400)

    /// Destructive intent (Remove, Disconnect, Sign Out).
    public static let destructive = Color(hex: 0xEF4444)
    /// The wash behind an open side menu — a touch deeper than `canvas`.
    public static let scrim = Color(hex: 0x040406)

    /// Critic-score bands (Metacritic-style). Previously raw hex at the call site in BOTH apps,
    /// which made these the only greens and reds in Seret living outside the palette.
    public static let ratingGood = Color(hex: 0x00CE7A)
    public static let ratingMid  = Color(hex: 0xFFCC33)
    public static let ratingBad  = Color(hex: 0xFF6874)

    public static let goldGradient = LinearGradient(
        colors: [goldLight, gold, goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    public static let markGradient = LinearGradient(
        colors: [goldBright, goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Maps a profile's `colorTag` to its avatar colour; defaults to gold.
    public static func color(for tag: String) -> Color {
        switch tag {
        case "blue":   return Color(hex: 0x3B82F6)
        case "green":  return Color(hex: 0x22C55E)
        case "red":    return destructive
        case "purple": return Color(hex: 0xA855F7)
        default:       return gold
        }
    }
}
