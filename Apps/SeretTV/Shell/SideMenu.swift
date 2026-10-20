import DebridUI
import SwiftUI

/// The left navigation, Plex style. At rest it is a floating glass capsule of icons, vertically
/// centred at the left edge; when the menu opens, the capsule's background grows into a floating
/// rounded panel, labels and section headers fade in beside a **fixed** icon column, and a single
/// white pill slides to the focused row.
///
/// Every row is ONE view in both states and a focus target in both — see `SideMenuRow`. Row frames
/// stay capsule-wide in BOTH states (labels draw past them when open), so the menu never overlaps
/// the page geometrically and RIGHT from any row always finds the page.
///
/// The scrim is NOT drawn here — it belongs to the shell, because it has to cover content this
/// view does not own.
struct SideMenu: View {
    let selected: SideMenuItem
    let profileName: String
    let profileAvatar: String
    let profileColorTag: String
    var focus: FocusState<SideMenuItem?>.Binding
    /// Whether the panel is open. Owned by the shell, NOT derived from `focus` here — tvOS parks
    /// focus on this menu unprompted (it is the top-leading view) and refuses to hand it back after
    /// a selection, so focus-presence would keep the menu open over the page you just chose.
    let expanded: Bool
    let onSelect: (SideMenuItem) -> Void
    let onProfile: () -> Void

    /// The collapsed capsule's width — also the width of the fixed icon column in both states.
    static let capsuleWidth: CGFloat = 92
    /// The open panel's width.
    static let panelWidth: CGFloat = 560
    /// How much of the screen's leading edge the collapsed menu claims: capsule (36 + 92) plus a
    /// gutter. Root pages start here, measured from the SCREEN edge — see `sideMenuContentInset()`.
    static let footprint: CGFloat = 150
    /// The capsule and panel's distance from the screen's leading edge (inside the TV's overscan).
    static let leadingGap: CGFloat = 36
    /// The open panel's distance from the top and bottom of the screen.
    static let panelInset: CGFloat = 40
    /// Row pitch, collapsed and open. The column has zero spacing, so this IS the gap between rows.
    static let collapsedRowHeight: CGFloat = 60
    static let rowHeight: CGFloat = 68
    /// The white focus marker: a circle behind the icon when collapsed, a full-row pill when open.
    static let pillCircle: CGFloat = 56
    static let pillHeight: CGFloat = 62
    static let pillInset: CGFloat = 14

    /// The row the pill sits on. While focus is in the page it stays (invisible) on the last focused
    /// row — moving it then would show as a jump while it fades out. When focus comes back it is
    /// set UNANIMATED to whichever row focus entered and only fades in there, so it never slides in
    /// from a stale row. Only moves between rows WITHIN the menu slide.
    @State private var pillItem: SideMenuItem?

    private var focusedItem: SideMenuItem? { focus.wrappedValue }
    private var morph: Animation { expanded ? Theme.Anim.panelOpen : Theme.Anim.panelClose }

    var body: some View {
        column
            .frame(width: expanded ? Self.panelWidth : Self.capsuleWidth)
            // Collapsed, the column hugs its rows and sits centred; open, it fills the panel.
            .frame(maxHeight: expanded ? .infinity : nil)
            .backgroundPreferenceValue(SideMenuRowBoundsKey.self) { bounds in pill(in: bounds) }
            // The dark text ON the pill: every row drawn again in the focus-text colour, masked to
            // the pill's own shape at its own (animated) position — so the text inverts exactly
            // where the pill is, mid-slide included, rather than a row flipping on its own clock.
            .overlayPreferenceValue(SideMenuRowBoundsKey.self) { bounds in invertedRows(in: bounds) }
            .background { SideMenuPanelBackground(expanded: expanded) }
            .frame(maxHeight: .infinity)
            .animation(morph, value: expanded)
            // ONE focus target spanning the full height, so LEFT from the first item of any row
            // lands here. A section widens a target; it does not trap focus. Its width is the
            // capsule's when collapsed, so it never covers the page.
            .focusSection()
            // …and where LEFT lands is the page you are on, as in every Apple TV app. Left to
            // geometry it was whichever row sat level with the focused control: Library from Home's
            // Resume, Movies from a card a little higher — so Select from the menu opened a
            // different page each time. `.userInitiated` is what applies it to a press, not just to
            // launch focus.
            .defaultFocus(focus, selected, priority: .userInitiated)
            .padding(.leading, Self.leadingGap)
            .padding(.vertical, Self.panelInset)
            // A layout-only wrapper (not focusable, not a section) so the menu can sit in the
            // overscan margin the page's safe area keeps clear.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .ignoresSafeArea()
            .onAppear { if pillItem == nil { pillItem = focusedItem ?? selected } }
            .onChange(of: focusedItem) { old, new in
                guard let new else { return }
                if old == nil {
                    // Focus entering from the page: no slide from wherever the pill was parked.
                    var entry = Transaction()
                    entry.disablesAnimations = true
                    withTransaction(entry) { pillItem = new }
                } else {
                    withAnimation(Theme.Anim.pill) { pillItem = new }
                }
            }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Profiles are switched off — the menu starts at Search. See `ProfilesFeature`.
            // ⚠️ Re-enabling Profiles needs spacing between the avatar row and Search (the old
            // rail had a 58pt gap); the column has zero spacing, so they would touch.
            if ProfilesFeature.isEnabled {
                profileRow
            }
            ForEach(SideMenuItem.mainRows) { item in
                if let section = item.startsSection {
                    SideMenuSectionHeader(title: section.title, expanded: expanded)
                }
                row(item)
            }
            // Open, this pushes Settings to the bottom of the panel; collapsed, it takes nothing.
            Spacer(minLength: 0)
                .frame(maxHeight: expanded ? .infinity : 0)
            SideMenuDivider(expanded: expanded)
            row(.settings)
        }
        .padding(.vertical, expanded ? 30 : 16)
    }

    private func row(_ item: SideMenuItem) -> some View {
        SideMenuRow(item: item, selected: item == selected, expanded: expanded) {
            onSelect(item)
        }
        .focused(focus, equals: item)
        .anchorPreference(key: SideMenuRowBoundsKey.self, value: .bounds) { [item: $0] }
    }

    /// The single white pill. One persistent view whose frame follows the focused row, so it
    /// slides rather than fading between rows.
    private func pill(in bounds: [SideMenuItem: Anchor<CGRect>]) -> some View {
        GeometryReader { proxy in
            pillShape(in: bounds, proxy: proxy, fill: Theme.Palette.focus)
        }
    }

    /// The pill's capsule at the pill item's row — the pill itself, and the inverted layer's mask.
    @ViewBuilder
    private func pillShape(in bounds: [SideMenuItem: Anchor<CGRect>], proxy: GeometryProxy,
                           fill: Color) -> some View {
        if let item = pillItem, let anchor = bounds[item] {
            let rect = proxy[anchor]
            // Open, the pill spans the panel, not the row: rows keep a capsule-wide frame.
            let width = expanded ? Self.panelWidth - 2 * Self.pillInset : Self.pillCircle
            let height = expanded ? Self.pillHeight : Self.pillCircle
            Capsule(style: .continuous)
                .fill(fill)
                .frame(width: width, height: height)
                .offset(x: expanded ? rect.minX + Self.pillInset
                                    : rect.minX + (Self.capsuleWidth - Self.pillCircle) / 2,
                        y: rect.midY - height / 2)
                .opacity(focusedItem == nil ? 0 : 1)
                .animation(Theme.Anim.focus, value: focusedItem == nil)
        }
    }

    /// Every row's icon and label again, dark, showing only through the pill. Not focusable, not
    /// hit-testable, hidden from VoiceOver — the real rows below are the menu.
    private func invertedRows(in bounds: [SideMenuItem: Anchor<CGRect>]) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                // The avatar row has no glyph to invert.
                ForEach(SideMenuItem.allCases.filter { $0 != .profile && bounds[$0] != nil }) { item in
                    let rect = proxy[bounds[item]!]
                    SideMenuRowContent(item: item, expanded: expanded)
                        .frame(width: rect.width, height: rect.height, alignment: .leading)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
            .foregroundStyle(Theme.Palette.onFocus)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .mask(alignment: .topLeading) {
                pillShape(in: bounds, proxy: proxy, fill: .black)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var profileRow: some View {
        Button(action: onProfile) {
            HStack(spacing: 0) {
                AvatarCircle(token: profileAvatar, diameter: 48, colorTag: profileColorTag)
                    .frame(width: Self.capsuleWidth)
                SideMenuLabel(text: profileName, expanded: expanded)
            }
            // Capsule-wide in both states, like every row — see `SideMenuRow`.
            .frame(width: Self.capsuleWidth,
                   height: expanded ? Self.rowHeight + 16 : Self.collapsedRowHeight + 8,
                   alignment: .leading)
        }
        .buttonStyle(SideMenuRowStyle(selected: false, expanded: expanded))
        // Bound to the SAME focus state as every other row — without this, focusing the avatar
        // leaves the menu collapsed while looking focused.
        .focused(focus, equals: .profile)
        .anchorPreference(key: SideMenuRowBoundsKey.self, value: .bounds) { [.profile: $0] }
    }
}

/// Every row's bounds, keyed by item, so the menu can draw ONE pill at the focused row.
struct SideMenuRowBoundsKey: PreferenceKey {
    static let defaultValue: [SideMenuItem: Anchor<CGRect>] = [:]

    static func reduce(value: inout [SideMenuItem: Anchor<CGRect>],
                       nextValue: () -> [SideMenuItem: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The capsule that grows into the panel: one rounded rectangle whose frame and corner animate
/// with the menu. Glass at rest; the near-opaque navy panel fill when open, so labels sit on the
/// panel rather than on the page.
private struct SideMenuPanelBackground: View {
    let expanded: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: expanded ? 32 : SideMenu.capsuleWidth / 2,
                                     style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape.fill(LinearGradient(colors: [Theme.Palette.panelTop, Theme.Palette.panelBottom],
                                          startPoint: .top, endPoint: .bottom))
                    .opacity(expanded ? 1 : 0.72)
            }
            .overlay { shape.strokeBorder(Theme.Palette.hairline, lineWidth: 1) }
            .shadow(color: .black.opacity(expanded ? 0.5 : 0.35),
                    radius: expanded ? 40 : 15, y: expanded ? 30 : 8)
    }
}

/// "Discover" / "Yours" above their rows, with a hairline rule. Always in the hierarchy; collapsed
/// it has zero height and is invisible, open it grows to 44.
private struct SideMenuSectionHeader: View {
    let title: String
    let expanded: Bool

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.seret(22, .medium))
                .foregroundStyle(Theme.Palette.textTertiary)
                .fixedSize()
            Rectangle()
                .fill(Theme.Palette.hairline)
                .frame(height: 1)
        }
        .padding(.leading, 30)
        .padding(.trailing, 34)
        .padding(.top, 8)
        // Fades with the labels, on the morph's own clock — see `SideMenuWordFade`.
        .modifier(SideMenuWordFade(expanded: expanded))
        .frame(width: expanded ? SideMenu.panelWidth : SideMenu.capsuleWidth,
               height: expanded ? 44 : 0, alignment: .leading)
        .clipped()
        // A heading for VoiceOver when it is on screen; nothing while it is collapsed away.
        .accessibilityHidden(!expanded)
        .accessibilityAddTraits(expanded ? .isHeader : [])
    }
}

/// The rule above Settings: a short line inside the capsule, the panel's width when open.
private struct SideMenuDivider: View {
    let expanded: Bool

    var body: some View {
        Rectangle()
            .fill(Theme.Palette.hairline)
            .frame(width: expanded ? SideMenu.panelWidth - 60 : 40, height: 1)
            .frame(width: expanded ? SideMenu.panelWidth : SideMenu.capsuleWidth)
            .padding(.vertical, 10)
    }
}

/// The dimming wash behind an open menu: a flat scrim over the whole page. The open panel has its
/// own near-opaque fill, so the labels sit on the panel, not on the washed page.
struct SideMenuScrim: View {
    let visible: Bool

    var body: some View {
        Theme.Palette.scrim
            .ignoresSafeArea()
            .opacity(visible ? 1 : 0)
            .animation(visible ? Theme.Anim.panelOpen : Theme.Anim.panelClose, value: visible)
            .allowsHitTesting(false)
    }
}

extension View {
    /// Starts a root page at `SideMenu.footprint` from the SCREEN's leading edge, clear of the
    /// collapsed capsule. The capsule sits in the overscan margin, so the inset ignores the leading
    /// safe area rather than adding to it. Root pages only — pushed pages stay full-bleed.
    func sideMenuContentInset() -> some View {
        padding(.leading, SideMenu.footprint)
            .ignoresSafeArea(.container, edges: .leading)
    }
}
