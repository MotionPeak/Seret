import SwiftUI

/// Primary action: the gold gradient capsule with a glow that brightens under the pointer.
struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { GoldButtonBody(configuration: configuration) }
}

private struct GoldButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(Theme.Typo.headline())
            .foregroundStyle(Theme.Palette.onGold)
            .padding(.vertical, 9).padding(.horizontal, 18)
            .background(Theme.Palette.goldGradient, in: Capsule())
            .goldGlow(hovering ? 20 : 14, opacity: configuration.isPressed ? 0.2 : (hovering ? 0.6 : 0.42))
            .scaleEffect(configuration.isPressed ? 0.97 : (hovering && isEnabled ? 1.03 : 1))
            .opacity(isEnabled ? 1 : 0.45)
            .animation(Theme.Motion.quick, value: hovering)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

/// Secondary action: a Liquid Glass capsule.
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { GlassButtonBody(configuration: configuration) }
}

private struct GlassButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(Theme.Typo.headline())
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.vertical, 9).padding(.horizontal, 16)
            .glassEffect(.regular.interactive(), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : (hovering && isEnabled ? 1.03 : 1))
            .opacity(isEnabled ? 1 : 0.45)
            .animation(Theme.Motion.quick, value: hovering)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}
