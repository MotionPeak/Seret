import SwiftUI

/// Primary / secondary action button for Detail & Add, with an explicit focus state so it never
/// falls back to the default tvOS capsule (which can render white-on-white when focused).
///
/// As in Plex, EVERY action rests as glass with white content, and focus alone turns a button
/// solid white with dark content. A resting white CTA beside a focused white button would leave
/// two candidates for "where am I", so the CTA is only slightly heavier at rest:
///   prominent   → glass pill + a faint white outline + semibold text (the Play / Resume CTA)
///   default     → glass pill, medium text
///   destructive → red text on glass, red fill on focus (Remove keeps its intent)
/// Focused (non-destructive): white pill, `onFocus` text, 1.04 lift.
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
                .font(.seret(Theme.Typography.cardSize, prominent ? .semibold : .medium))
                .foregroundStyle(textColor)
                .padding(.horizontal, 30).padding(.vertical, 16)
                .background(fill, in: Capsule())
                // Always present, faded out on focus — the CTA's only resting distinction.
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                    .opacity(prominent && !focused ? 1 : 0))
                .scaleEffect(focused ? Theme.Anim.buttonFocusScale : 1)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(Theme.Anim.focus, value: focused)
        }

        private var redColor: Color { Theme.Palette.destructive }

        private var textColor: Color {
            if destructive { return focused ? .white : redColor }
            return focused ? Theme.Palette.onFocus : Theme.Palette.textPrimary
        }

        private var fill: Color {
            if destructive { return focused ? redColor : Theme.Palette.glass }
            return focused ? Theme.Palette.focus : Theme.Palette.glass
        }
    }
}

/// The primary CTA (`SeretActionButtonStyle(prominent: true)`): glass with a faint outline at
/// rest, a white pill with dark text when focused — under the name the title page and player use.
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
                .background(focused ? AnyShapeStyle(Theme.Palette.glass)
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
