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
            SideMenuRowContent(item: item, expanded: expanded)
        }
        .buttonStyle(SideMenuRowStyle(selected: selected, expanded: expanded))
    }
}

/// A row's icon and label in the row's frame — drawn by the row itself, and again, dark, by
/// `SideMenu`'s inverted layer inside the sliding pill.
struct SideMenuRowContent: View {
    let item: SideMenuItem
    let expanded: Bool

    var body: some View {
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
}

/// A row's label. Always laid out; fades in late in the panel's growth, and out at once.
///
/// ⚠️ `.contentTransition(.identity)` is load-bearing. A collapse also changes the label's tint
/// (`SideMenuRowStyle`: bright when open, dimmed when collapsed), and Text's default content
/// transition re-renders a restyled Text on its own path — detached from the layout animation that
/// moves its row. So on every collapse the labels raced to their collapsed rows at about twice the
/// icons' pace: a column of labels sliding down the panel, out of line with its icons
/// (`.superpowers/plex-redesign-screens/13-menu-collapse-glitch.png`). `.interpolate` drifts too.
/// The cost: the tint snaps rather than cross-fades, which only shows on the focused row.
struct SideMenuLabel: View {
    let text: String
    let expanded: Bool

    var body: some View {
        Text(text)
            .navLabel()
            .fixedSize()
            .lineLimit(1)
            .contentTransition(.identity)
            .padding(.leading, 4)
            .modifier(SideMenuWordFade(expanded: expanded, nudge: 14))
    }
}

/// How the menu's words — row labels and section headers — fade: on the panel morph's own clock.
///
/// The fade is a function of the morph's progress, interpolated frame by frame in the morph's
/// transaction like every position in the menu, rather than a second animation with its own curve.
/// One clock means a word can never be out of step with the row that carries it; the windows below
/// still give "out at once, in late".
struct SideMenuWordFade: ViewModifier, Animatable {
    /// 0 collapsed … 1 open. Animated by the morph.
    var progress: Double
    /// The direction of travel, which picks the fade's window.
    let opening: Bool
    /// How far a hidden word sits to the left of its place.
    let nudge: CGFloat

    init(expanded: Bool, nudge: CGFloat = 0) {
        progress = expanded ? 1 : 0
        opening = expanded
        self.nudge = nudge
    }

    // `nonisolated`: SwiftUI drives `animatableData` off the main actor while interpolating — see
    // `CoverFlowReel`. A Double on a value type; nothing to race on.
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let shown = opacity
        content
            .opacity(shown)
            .offset(x: (shown - 1) * nudge)
    }

    /// Closing, the words are gone in the first quarter of the morph (~0.13s of `panelClose`'s
    /// slow start), so a closing panel never carries readable text. Opening, they wait until the
    /// panel is half grown and arrive with it.
    private var opacity: Double {
        let t = opening ? (progress - 0.5) / 0.5 : (progress - 0.75) / 0.25
        return min(max(t, 0), 1)
    }
}

/// A menu row's tint. The white fill behind the focused row is `SideMenu`'s sliding pill, and the
/// dark text on it is `SideMenu`'s inverted layer, masked to the pill — so the row itself never
/// turns dark. It used to, the instant focus arrived, while the pill was still sliding over from
/// the last row: the new row went dark on the navy panel and the old one white on the white pill,
/// so the slide read as a jump (owner, on the real Apple TV: "it highlights it before even the
/// white outline goes there").
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
                // The morph, re-asserted on the row's own content. Select collapses the menu from
                // inside this button's press, and without this the pressed row's icon and label
                // moved on the press's transaction instead — ahead of every other row, off the
                // pill that was still sliding with the panel.
                .animation(expanded ? Theme.Anim.panelOpen : Theme.Anim.panelClose, value: expanded)
                .foregroundStyle(tint)
                .background(alignment: .leading) {
                    // The pill's geometry rule, past the row's capsule-wide frame: full row when
                    // open, the icon circle when collapsed — so it shrinks WITH the panel's morph
                    // instead of overhanging the closing panel.
                    Capsule(style: .continuous)
                        .fill(Theme.Palette.glassFaint)
                        .frame(width: expanded ? SideMenu.panelWidth - 2 * SideMenu.pillInset
                                               : SideMenu.pillCircle,
                               height: expanded ? SideMenu.pillHeight : SideMenu.pillCircle)
                        .offset(x: expanded ? SideMenu.pillInset
                                            : (SideMenu.capsuleWidth - SideMenu.pillCircle) / 2)
                        .opacity(selected && expanded && !focused ? 1 : 0)
                }
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(Theme.Anim.pill, value: focused)
        }

        private var tint: Color {
            // A focused row is bright like an open one: under the pill it is white on white, and
            // the inverted layer draws it dark there.
            if focused || selected || expanded { return Theme.Palette.textPrimary }
            return Theme.Palette.textSecondary
        }
    }
}
