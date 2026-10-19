import SwiftUI

/// One side-menu row: a fixed-width icon column (centred in the capsule) and a label that only
/// shows when the menu is open. The white focus marker is NOT drawn here — `SideMenu` draws one
/// pill for the whole menu, so it can slide between rows.
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
                    .font(.system(size: 30, weight: .regular))
                    .frame(width: SideMenu.capsuleWidth)
                SideMenuLabel(text: item.title, expanded: expanded)
            }
            // ⚠️ The row's FRAME — its focus geometry — is the capsule's width in BOTH states; the
            // label just draws past it when the panel is open. A panel-wide frame (36–596) put
            // nearly every page item "under" the row rather than to its right, so RIGHT from a
            // row whose band met nothing beyond 596 went nowhere: a dead remote on the real
            // Movies page (Movies row between the genre pills and the first rail). Kept narrow,
            // the page's focus section (x ≥ 150) is always strictly to the right of every row.
            .frame(width: SideMenu.capsuleWidth,
                   height: expanded ? SideMenu.rowHeight : SideMenu.collapsedRowHeight,
                   alignment: .leading)
        }
        .buttonStyle(SideMenuRowStyle(selected: selected, expanded: expanded))
    }
}

/// A row's label. Always laid out; fades in a beat after the panel starts to grow, and out at once.
struct SideMenuLabel: View {
    let text: String
    let expanded: Bool

    var body: some View {
        Text(text)
            .navLabel()
            .fixedSize()
            .lineLimit(1)
            .padding(.leading, 4)
            .opacity(expanded ? 1 : 0)
            .offset(x: expanded ? 0 : -14)
            .animation(expanded ? Theme.Anim.panelOpen.delay(0.1) : .easeOut(duration: 0.12),
                       value: expanded)
    }
}

/// A menu row's tint. The white fill behind the focused row is `SideMenu`'s sliding pill; this
/// only turns the focused row's content dark so it reads on it.
///
/// Collapsed, the current page's icon is the bright one and the rest are dimmed, so the capsule
/// says where you are. Open, every label is bright (the panel is near-opaque) and the current page
/// keeps a faint glass pill, so it stays findable once the white pill has moved off it.
struct SideMenuRowStyle: ButtonStyle {
    let selected: Bool
    let expanded: Bool

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, selected: selected, expanded: expanded)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        let expanded: Bool
        @Environment(\.isFocused) private var focused: Bool

        var body: some View {
            configuration.label
                .foregroundStyle(tint)
                .background(alignment: .leading) {
                    // Drawn at the pill's open geometry, past the row's capsule-wide frame.
                    Capsule(style: .continuous)
                        .fill(Theme.Palette.glassFaint)
                        .frame(width: SideMenu.panelWidth - 2 * SideMenu.pillInset,
                               height: SideMenu.pillHeight)
                        .offset(x: SideMenu.pillInset)
                        .opacity(selected && expanded && !focused ? 1 : 0)
                }
                .opacity(configuration.isPressed ? 0.7 : 1)
                // The pill's curve, so the tint and the sliding pill arrive together.
                .animation(Theme.Anim.pill, value: focused)
        }

        private var tint: Color {
            if focused { return Theme.Palette.onFocus }
            if selected || expanded { return Theme.Palette.textPrimary }
            return Theme.Palette.textSecondary
        }
    }
}
