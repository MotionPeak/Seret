import SwiftUI

extension View {
    /// Soft gold halo for active/interactive elements.
    func goldGlow(_ radius: CGFloat = 16, opacity: Double = 0.45) -> some View {
        shadow(color: Color(hex: 0xEBC11D, alpha: opacity), radius: radius)
    }

    /// Dark frosted bar/sheet background (blur + black tint + hairline top).
    func glassBackground(topHairline: Bool = true) -> some View {
        background(.ultraThinMaterial)
            .background(Theme.Palette.canvas.opacity(0.55))
            .overlay(alignment: .top) {
                if topHairline { Theme.Palette.hairline.frame(height: 0.5) }
            }
    }

    /// Tap feedback: scale down on press.
    func pressable() -> some View { buttonStyle(PressableButtonStyle()) }
}

/// Scales content to 0.96 while pressed. Use on tappable cards/posters.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

/// Full-screen Gold Glass canvas wash. Put behind screen content.
struct CanvasBackground: View {
    var body: some View {
        ZStack {
            Theme.Palette.canvas
            Theme.Palette.canvasGlow
        }
        .ignoresSafeArea()
    }
}
