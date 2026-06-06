import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// Single source of truth for the mobile "Gold Glass" look. tvOS is unaffected.
enum Theme {
    enum Palette {
        static let gold        = Color(hex: 0xEBC11D)
        static let goldLight   = Color(hex: 0xF6D24A)
        static let goldBright  = Color(hex: 0xFDE98A)
        static let goldDeep    = Color(hex: 0xC8930A)
        static let goldGlow    = Color(hex: 0xEBC11D, alpha: 0.40)
        static let canvas      = Color(hex: 0x08080A)
        static let trueBlack   = Color.black
        static let surface1    = Color(hex: 0x141416)
        static let surface2    = Color(hex: 0x1C1C1F)
        static let hairline    = Color.white.opacity(0.09)
        static let chipFill    = Color.white.opacity(0.12)
        static let textPrimary   = Color(hex: 0xF5F5F7)
        static let textSecondary = Color(hex: 0x8A8A90)
        static let textTertiary  = Color(hex: 0x5A5A60)

        static let goldGradient = LinearGradient(
            colors: [goldLight, gold, goldDeep],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        static let markGradient = LinearGradient(
            colors: [goldBright, goldDeep],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        /// Faint top glow used as a screen background wash.
        static let canvasGlow = RadialGradient(
            colors: [Color(hex: 0xEBC11D, alpha: 0.14), .clear],
            center: .init(x: 0.8, y: -0.05), startRadius: 0, endRadius: 520)
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
