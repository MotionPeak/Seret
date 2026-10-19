import SwiftUI

/// A secondary action that is only an icon until you land on it: at rest a 78pt glass circle with
/// the symbol, focused a white capsule that reveals its title beside the icon. The width animates,
/// so the buttons after it in a row slide over smoothly instead of jumping.
///
/// Give it a `Label` — the icon and the title are styled separately:
///
///     Button { … } label: { Label("Trailer", systemImage: "play.rectangle") }
///         .buttonStyle(ExpandingIconButtonStyle())
///
/// The title is always laid out and only its width and opacity change, so the focused view never
/// swaps branches (see CLAUDE.md, focus traps).
struct ExpandingIconButtonStyle: ButtonStyle {
    /// The resting circle's diameter, which is also the focused capsule's height.
    static let diameter: CGFloat = 78

    func makeBody(configuration: Configuration) -> some View {
        Render(configuration: configuration)
    }

    private struct Render: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .labelStyle(ExpandingLabelStyle(expanded: focused))
                .foregroundStyle(focused ? Theme.Palette.onFocus : Theme.Palette.textPrimary)
                .frame(minWidth: ExpandingIconButtonStyle.diameter,
                       minHeight: ExpandingIconButtonStyle.diameter,
                       maxHeight: ExpandingIconButtonStyle.diameter)
                .background(focused ? Theme.Palette.focus : Theme.Palette.glass, in: Capsule())
                .scaleEffect(focused ? Theme.Anim.buttonFocusScale : 1)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(Theme.Anim.focus, value: focused)
        }
    }
}

/// Icon in a fixed-width column (so it never shifts as the capsule grows), title in a frame whose
/// width runs 0 → its natural width. A zero-width frame plus `.clipped()` keeps the text out of the
/// resting circle without removing it from the hierarchy.
private struct ExpandingLabelStyle: LabelStyle {
    let expanded: Bool

    /// Icon column: wide enough for the broadest symbols, centred in the 78pt circle at rest.
    private let iconColumn: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: expanded ? 12 : 0) {
            configuration.icon
                .font(.system(size: 30, weight: .semibold))
                .frame(width: iconColumn)
            configuration.title
                .font(.seret(26, .semibold))
                .lineLimit(1)
                .fixedSize()
                .frame(width: expanded ? nil : 0, alignment: .leading)
                .opacity(expanded ? 1 : 0)
                .clipped()
        }
        .padding(.leading, (ExpandingIconButtonStyle.diameter - iconColumn) / 2)
        .padding(.trailing, expanded ? 30 : (ExpandingIconButtonStyle.diameter - iconColumn) / 2)
    }
}
