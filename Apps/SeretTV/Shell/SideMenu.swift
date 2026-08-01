import DebridUI
import SwiftUI

/// The left navigation. At rest it is a 120pt icon rail; when focus lands in it the panel widens
/// and labels fade in beside a **fixed** icon column, so nothing on screen shifts.
///
/// The scrim is NOT drawn here — it belongs to the shell, because it has to cover content this
/// view does not own.
struct SideMenu: View {
    let selected: SideMenuItem
    let profileName: String
    let profileAvatar: String
    let profileColorTag: String
    var focus: FocusState<SideMenuItem?>.Binding
    let onSelect: (SideMenuItem) -> Void
    let onProfile: () -> Void

    static let railWidth: CGFloat = 120
    static let panelWidth: CGFloat = 470
    /// Row pitch. The VStack has zero spacing, so this IS the gap between rows.
    static let rowHeight: CGFloat = 96

    private var expanded: Bool { focus.wrappedValue != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            profileRow
            Spacer().frame(height: 58)
            ForEach(SideMenuItem.mainRows) { item in
                SideMenuRow(item: item, selected: item == selected, expanded: expanded) {
                    onSelect(item)
                }
                .focused(focus, equals: item)
            }
            Spacer(minLength: 0)
            SideMenuRow(item: .settings, selected: selected == .settings, expanded: expanded) {
                onSelect(.settings)
            }
            .focused(focus, equals: .settings)
        }
        .padding(.vertical, 60)
        .frame(width: expanded ? Self.panelWidth : Self.railWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.22), value: expanded)
        // ONE focus target spanning the full height, so LEFT from the first item of any row lands
        // here. A section widens a target; it does not trap focus.
        .focusSection()
    }

    private var profileRow: some View {
        Button(action: onProfile) {
            HStack(spacing: 0) {
                ProfileAvatarImage(token: profileAvatar, diameter: 52, colorTag: profileColorTag)
                    .frame(width: Self.railWidth)
                Text(profileName)
                    .navLabel()
                    .fixedSize()
                    .lineLimit(1)
                    .opacity(expanded ? 1 : 0)
            }
            .frame(width: expanded ? Self.panelWidth : Self.railWidth,
                   height: Self.rowHeight, alignment: .leading)
            .clipped()
        }
        .buttonStyle(SideMenuRowStyle(selected: false))
        // Bound to the SAME focus state as every other row — without this, focusing the avatar
        // leaves the menu collapsed while looking focused.
        .focused(focus, equals: .profile)
    }
}

/// The dimming wash behind an open menu. A left-to-right gradient rather than a flat panel, so the
/// page reads as *under* the menu instead of being replaced by it.
struct SideMenuScrim: View {
    let visible: Bool

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: 0x040406, alpha: 0.96), location: 0),
                .init(color: Color(hex: 0x040406, alpha: 0.96), location: 0.24),
                .init(color: Color(hex: 0x040406, alpha: 0.0), location: 0.53),
            ],
            startPoint: .leading, endPoint: .trailing)
        .ignoresSafeArea()
        .opacity(visible ? 1 : 0)
        .animation(.easeOut(duration: 0.22), value: visible)
        .allowsHitTesting(false)
    }
}
