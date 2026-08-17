import SwiftUI

/// Primary / secondary action button for Detail & Add. Gold Glass with an explicit focus state, so
/// it never falls back to the default tvOS capsule (which can render white-on-white when focused).
///   prominent → solid gold pill, black text (the Play / Resume CTA)
///   default   → glass pill, primary text
///   destructive → red text, red fill on focus (Remove keeps its intent)
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
                .overlay(Capsule().strokeBorder(strokeColor, lineWidth: focused ? 3 : 1))
                .scaleEffect(focused ? Theme.Anim.focusScale : 1)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .goldGlow(focused && !destructive ? 22 : 0, opacity: 0.35)
                .animation(Theme.Anim.focus, value: focused)
        }

        private var redColor: Color { Color(hex: 0xEF4444) }

        private var textColor: Color {
            if focused { return destructive ? .white : .black }
            if prominent { return .black }
            return destructive ? redColor : Theme.Palette.textPrimary
        }

        /// A focused button used to differ from an unfocused PROMINENT one only by a soft glow and
        /// a 1.06 scale — both drew the same gold gradient with the same black text, so the focused
        /// Play on Detail was indistinguishable from the unfocused Resume on Home (measured: core
        /// fill 172,139,21 vs 174,141,23). At ten feet that is no cue at all.
        ///
        /// Focus now brightens the fill AND draws the gold ring the rest of the app already uses as
        /// its focus idiom (SeretRowStyle, the player's settings and subtitle panels), so the CTA
        /// speaks the same language as every other focusable surface instead of being the one
        /// control you cannot locate.
        private var fill: AnyShapeStyle {
            if focused { return destructive ? AnyShapeStyle(redColor) : AnyShapeStyle(Theme.Palette.goldGradient) }
            if prominent { return AnyShapeStyle(Theme.Palette.goldDeep) }   // resting: flatter, deeper gold
            return AnyShapeStyle(Color.white.opacity(0.10))
        }

        private var strokeColor: Color {
            if focused { return destructive ? .white.opacity(0.85) : Theme.Palette.goldBright }
            return .white.opacity(0.10)
        }
    }
}

/// A truly chrome-free button: renders only its label (plus a press dim), with NO focus platter.
/// tvOS draws a translucent rounded "platter" behind focused `.plain` Buttons even with
/// `.focusEffectDisabled()`, so for views that supply their OWN focus cue (scale/glow — the profile
/// tiles, avatar grid, colour swatches) use this instead of `.plain` to kill that grey card.
struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// A wide, full-width list row (e.g. a version in the Detail "Versions" list) on a glass surface,
/// with a clear gold focus border instead of the default tvOS highlight.
struct SeretRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Render(configuration: configuration) }
    private struct Render: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .padding(.horizontal, 22).padding(.vertical, 16)
                .background(focused ? AnyShapeStyle(Theme.Palette.gold.opacity(0.16))
                                    : AnyShapeStyle(Theme.Palette.surface2),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(focused ? Theme.Palette.gold : Theme.Palette.hairline,
                                  lineWidth: focused ? 2 : 1))
                .scaleEffect(focused ? 1.02 : 1)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(Theme.Anim.focus, value: focused)
        }
    }
}
