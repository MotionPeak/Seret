import SwiftUI

/// The focus look for everything that is a picture — posters, landscape cards, episode stills,
/// cast, franchise and download tiles. Replaces `.buttonStyle(.card)`.
///
/// tvOS's `.card` draws its own platter, parallax and white-ish lift, none of which match a dark
/// navy page with white as the only accent. This draws the Plex idiom instead: the focused card
/// lifts to 1.08, a 4pt white ring sits just OUTSIDE its rounded edge (so it never covers the
/// artwork), and a soft drop shadow separates it from the row. No platter, no parallax, no glow.
///
/// The label is clipped to `cornerRadius`, so a label that is already rounded (most are) loses
/// nothing and one that is not gets the poster corner. The ring is always in the hierarchy and only
/// its opacity changes — a focused view must never swap branches (see CLAUDE.md, focus traps).
///
/// A long press that opens a context menu leaves the button's state behind when the menu closes
/// (measured, `-uiPreview library` and the signed-in Library grid): `isPressed` stays true — the
/// press's end went to the menu — and `\.isFocused` can stay false although the card has focus
/// again, so the card came back with no ring and no lift until the next arrow press. Two guards:
/// a press that focus left (the menu took it) no longer counts, and a card attached with
/// `focusCardButtonStyle()` takes its focus from a `@FocusState` on the button, which the focus
/// engine does restore.
struct FocusCardStyle: ButtonStyle {
    var cornerRadius: CGFloat = Theme.Layout.posterCorner
    /// The button's focus from a `@FocusState` on it (see `focusCardButtonStyle`); nil reads
    /// `\.isFocused`.
    var focused: Bool? = nil

    func makeBody(configuration: Configuration) -> some View {
        Render(configuration: configuration, cornerRadius: cornerRadius, focusOverride: focused)
    }

    private struct Render: View {
        let configuration: ButtonStyleConfiguration
        let cornerRadius: CGFloat
        let focusOverride: Bool?
        @Environment(\.isFocused) private var environmentFocused
        /// Focus left while the press was down: a context menu took it, and the press will never
        /// see its end. Cleared when the press state next changes.
        @State private var pressAbandoned = false

        var body: some View {
            let focused = focusOverride ?? environmentFocused
            configuration.label
                .focusCardChrome(focused: focused,
                                 pressed: configuration.isPressed && !pressAbandoned,
                                 cornerRadius: cornerRadius)
                .onChange(of: focused) { _, now in
                    if !now && configuration.isPressed { pressAbandoned = true }
                }
                .onChange(of: configuration.isPressed) { _, _ in pressAbandoned = false }
        }
    }
}

extension View {
    /// `FocusCardStyle`, with the card's focus read from a `@FocusState` on the button rather than
    /// `\.isFocused` — which a context menu can leave stale (see `FocusCardStyle`). For every card
    /// that carries a long-press menu, and harmless on any other.
    func focusCardButtonStyle(cornerRadius: CGFloat = Theme.Layout.posterCorner) -> some View {
        modifier(FocusCardButtonStyle(cornerRadius: cornerRadius))
    }
}

/// Its own `@FocusState`, so a focus change re-renders only this modifier, never the tile's art.
private struct FocusCardButtonStyle: ViewModifier {
    let cornerRadius: CGFloat
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .buttonStyle(FocusCardStyle(cornerRadius: cornerRadius, focused: focused))
    }
}

extension View {
    /// `FocusCardStyle`'s look on a PART of a larger focus target — an episode's still inside a
    /// lockup whose title and synopsis sit beneath it. The caller reads `\.isFocused` from inside
    /// the button's label and passes it here; the words under the still stay put.
    ///
    /// `anchor` is where the lift grows from: `.bottom` keeps a still's lift off the text below.
    func focusCardChrome(focused: Bool, pressed: Bool = false,
                         cornerRadius: CGFloat = Theme.Layout.posterCorner,
                         anchor: UnitPoint = .center) -> some View {
        modifier(FocusCardChrome(focused: focused, pressed: pressed, cornerRadius: cornerRadius,
                                 anchor: anchor))
    }
}

private struct FocusCardChrome: ViewModifier {
    let focused: Bool
    let pressed: Bool
    let cornerRadius: CGFloat
    let anchor: UnitPoint

    /// Ring width, drawn entirely outside the card.
    private let ring: CGFloat = 4

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                // Concentric with the card: its radius grows by exactly the ring's width.
                RoundedRectangle(cornerRadius: cornerRadius + ring, style: .continuous)
                    .strokeBorder(Theme.Palette.focus, lineWidth: ring)
                    .padding(-ring)
                    .opacity(focused ? 1 : 0)
            }
            .liftShadow(focused)
            .scaleEffect(pressed ? 0.96 : (focused ? Theme.Anim.focusScale : 1), anchor: anchor)
            .animation(Theme.Anim.focus, value: focused)
            .animation(Theme.Anim.focus, value: pressed)
    }
}
