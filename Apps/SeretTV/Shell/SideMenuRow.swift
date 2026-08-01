import SwiftUI

/// One side-menu row: a fixed-width icon column, a selection accent bar, and a label that only
/// appears when the menu is expanded.
///
/// ⚠️ This is ONE view in both states. The label is always in the hierarchy and is hidden by width
/// + opacity, never by an `if`. A branch swap under a focused view makes tvOS silently drop focus
/// to the first stable element — the defect behind `BrowseTile`'s search-keyboard bug and the Add
/// screen's unfocusable episode cards.
struct SideMenuRow: View {
    let item: SideMenuItem
    let selected: Bool
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // `.system` on purpose: this is an SF Symbol, not text.
                Image(systemName: item.icon)
                    .font(.system(size: 34, weight: .medium))
                    .frame(width: SideMenu.railWidth)
                accentBar
                Text(item.title)
                    .navLabel()
                    .fixedSize()
                    .lineLimit(1)
                    .opacity(expanded ? 1 : 0)
            }
            .frame(width: expanded ? SideMenu.panelWidth : SideMenu.railWidth,
                   height: SideMenu.rowHeight, alignment: .leading)
            .clipped()
        }
        .buttonStyle(SideMenuRowStyle(selected: selected))
    }

    /// The gold marker beside the active row. Present in the hierarchy at all times, for the same
    /// reason the label is.
    private var accentBar: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Theme.Palette.gold)
            .frame(width: 5, height: 44)
            .opacity(selected && expanded ? 1 : 0)
            .padding(.trailing, 11)
    }
}

/// Focus/selection tinting for a menu row. Mirrors `SeretPillStyle`'s explicit-colour approach so a
/// focused row is never white-on-white.
struct SideMenuRowStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, selected: selected)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @Environment(\.isFocused) private var focused: Bool

        var body: some View {
            configuration.label
                .foregroundStyle(tint)
                .background(focused ? Theme.Palette.gold.opacity(0.16) : .clear,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }

        private var tint: Color {
            if focused { return Theme.Palette.goldBright }
            if selected { return Theme.Palette.gold }
            return Theme.Palette.textSecondary
        }
    }
}
