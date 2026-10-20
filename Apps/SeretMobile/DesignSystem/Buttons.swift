import SwiftUI

/// Primary action: gold gradient pill with glow.
struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typo.headline())
            .foregroundStyle(Theme.Palette.onGold)
            .padding(.vertical, 11).padding(.horizontal, Theme.Space.xl)
            .background(Theme.Palette.goldGradient, in: Capsule())
            .goldGlow(14, opacity: configuration.isPressed ? 0.2 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

/// Secondary action: hairline-outlined pill on glass.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typo.headline())
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.vertical, 11).padding(.horizontal, Theme.Space.lg)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

/// A label that shows its title and icon, or its icon alone when space is short. The title stays
/// the accessibility label either way, so VoiceOver still reads "Watchlist", not "bookmark".
struct AdaptiveLabelStyle: LabelStyle {
    let iconOnly: Bool

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            Label(configuration).labelStyle(.iconOnly)
        } else {
            Label(configuration).labelStyle(.titleAndIcon)
        }
    }
}

#Preview {
    ZStack { CanvasBackground()
        VStack(spacing: 16) {
            Button("▶  Resume") {}.buttonStyle(GoldButtonStyle())
            Button("Use a token") {}.buttonStyle(GhostButtonStyle())
        }
    }
}
