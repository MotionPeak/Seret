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

/// tvOS "Gold Glass" tokens — mirrors the iPhone/iPad design system so the apps match.
enum Theme {
    enum Palette {
        static let gold        = Color(hex: 0xEBC11D)
        static let goldLight   = Color(hex: 0xF6D24A)
        static let goldBright  = Color(hex: 0xFDE98A)
        static let goldDeep    = Color(hex: 0xC8930A)
        static let goldGlow    = Color(hex: 0xEBC11D, alpha: 0.40)
        static let canvas      = Color(hex: 0x08080A)
        static let surface1    = Color(hex: 0x141416)
        static let surface2    = Color(hex: 0x1C1C1F)
        static let hairline    = Color.white.opacity(0.10)
        static let chipFill    = Color.white.opacity(0.12)
        static let textPrimary   = Color(hex: 0xF5F5F7)
        static let textSecondary = Color(hex: 0x9A9AA0)

        static let goldGradient = LinearGradient(
            colors: [goldLight, gold, goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        static let markGradient = LinearGradient(
            colors: [goldBright, goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        static let canvasGlow = RadialGradient(
            colors: [Color(hex: 0xEBC11D, alpha: 0.16), .clear],
            center: .init(x: 0.85, y: -0.1), startRadius: 0, endRadius: 1300)

        /// Maps a profile's `colorTag` to its avatar color; defaults to gold.
        static func color(for tag: String) -> Color {
            switch tag {
            case "blue":   return Color(hex: 0x3B82F6)
            case "green":  return Color(hex: 0x22C55E)
            case "red":    return Color(hex: 0xEF4444)
            case "purple": return Color(hex: 0xA855F7)
            default:        return gold
            }
        }
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
