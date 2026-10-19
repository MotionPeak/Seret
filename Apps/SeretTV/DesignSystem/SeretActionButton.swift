import SwiftUI

/// Primary / secondary action button for Detail & Add, with an explicit focus state so it never
/// falls back to the default tvOS capsule (which can render white-on-white when focused).
///   prominent   → white pill, dark text (the Play / Resume CTA)
///   default     → glass pill, white text; white pill, dark text when focused
///   destructive → red text on glass, red fill on focus (Remove keeps its intent)
/// NavigationLinks pick this up too (the Play CTAs are value-nav links).
struct SeretActionButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        Render(configuration: configuration, prominent: prominent, destructive: destructive)
    }

    private struct Render: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let destructive: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .font(.seret(Theme.Typography.cardSize, .semibold))
                .foregroundStyle(textColor)
                .padding(.horizontal, 30).padding(.vertical, 16)
                .background(fill, in: Capsule())
                .scaleEffect(focused ? Theme.Anim.buttonFocusScale : 1)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(Theme.Anim.focus, value: focused)
        }

        private var redColor: Color { Theme.Palette.destructive }

        private var textColor: Color {
            if destructive { return focused ? .white : redColor }
            if focused || prominent { return Theme.Palette.onFocus }
            return Theme.Palette.textPrimary
        }

        /// A resting prominent button is white too, so focus has to be told apart by more than the
        /// 1.04 lift: at rest the white is held back a little (it reads as a light grey on navy),
        /// focused it is the full white every other focused control uses.
        private var fill: Color {
            if destructive { return focused ? redColor : Theme.Palette.glass }
            if focused { return Theme.Palette.focus }
            if prominent { return Theme.Palette.focus.opacity(0.82) }
            return Theme.Palette.glass
        }
    }
}

/// The primary CTA — a white pill with dark text (`SeretActionButtonStyle(prominent: true)`), under
/// the name the title page and player use for it.
struct PrimaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SeretActionButtonStyle(prominent: true).makeBody(configuration: configuration)
    }
}

/// A truly chrome-free button: renders only its label (plus a press dim), with NO focus platter.
/// tvOS draws a translucent rounded "platter" behind focused `.plain` Buttons even with
/// `.focusEffectDisabled()`, so for views that supply their OWN focus cue (scale/ring — the profile
/// tiles, avatar grid, colour swatches) use this instead of `.plain` to kill that grey card.
struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// A wide, full-width list row (e.g. a version in the Detail "Versions" list) on a dark surface,
/// with a clear white focus ring instead of the default tvOS highlight.
struct SeretRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Render(configuration: configuration) }
    private struct Render: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .padding(.horizontal, 22).padding(.vertical, 16)
                .background(focused ? AnyShapeStyle(Color.white.opacity(0.18))
                                    : AnyShapeStyle(Theme.Palette.surface2),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(focused ? Theme.Palette.focus : Theme.Palette.hairline,
                                  lineWidth: focused ? 3 : 1))
                .scaleEffect(focused ? 1.02 : 1)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(Theme.Anim.focus, value: focused)
        }
    }
}
