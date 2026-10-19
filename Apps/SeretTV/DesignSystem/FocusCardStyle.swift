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
struct FocusCardStyle: ButtonStyle {
    var cornerRadius: CGFloat = Theme.Layout.posterCorner

    func makeBody(configuration: Configuration) -> some View {
        Render(configuration: configuration, cornerRadius: cornerRadius)
    }

    private struct Render: View {
        let configuration: ButtonStyleConfiguration
        let cornerRadius: CGFloat
        @Environment(\.isFocused) private var focused

        /// Ring width, drawn entirely outside the card.
        private let ring: CGFloat = 4

        var body: some View {
            configuration.label
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    // Concentric with the card: its radius grows by exactly the ring's width.
                    RoundedRectangle(cornerRadius: cornerRadius + ring, style: .continuous)
                        .strokeBorder(Theme.Palette.focus, lineWidth: ring)
                        .padding(-ring)
                        .opacity(focused ? 1 : 0)
                }
                .liftShadow(focused)
                .scaleEffect(configuration.isPressed ? 0.96 : (focused ? Theme.Anim.focusScale : 1))
                .animation(Theme.Anim.focus, value: focused)
                .animation(Theme.Anim.focus, value: configuration.isPressed)
        }
    }
}
