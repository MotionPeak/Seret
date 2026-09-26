import SwiftUI

/// A capsule pill button: the gold gradient + glow when selected, a faint white fill otherwise, a
/// small hover lift on the unselected state. Shared by `SeasonPills`, the genre strip and the
/// segment bar so every pill in the app looks and behaves the same.
struct PillButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(configuration: configuration, selected: selected)
    }
}

private struct PillButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let selected: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(selected ? Theme.Palette.onGold : Theme.Palette.textSecondary)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background { fill }
            .offset(y: hovering && !selected && !reduceMotion ? -2 : 0)
            .goldGlow(selected ? 10 : 0, opacity: selected ? 0.35 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.quick, value: hovering)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
            .onHover { hovering = $0 }
    }

    @ViewBuilder private var fill: some View {
        if selected {
            Capsule().fill(Theme.Palette.goldGradient)
        } else {
            Capsule().fill(Color.white.opacity(0.06))
        }
    }
}
