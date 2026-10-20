import DebridCore
import DebridUI
import SwiftUI

/// The iPad's Plex-style floating sidebar (mockup `m5-ipad-home`): a rounded navy panel inset from
/// the screen edges, with Search and Home on top, a "Discover" group (Movies, Shows), a "Yours"
/// group (Watchlist, Library) and Settings pinned to the bottom. The current page is a white pill.
///
/// Collapsing shrinks it to an icon-only capsule — every destination keeps its icon, so the current
/// page is never invisible (the same rule as SeretTV's collapsed side menu). The avatar row only
/// exists while profiles are switched on.
struct ShellSidebar: View {
    typealias Section = MainShell.Section

    static let expandedWidth: CGFloat = 252
    static let collapsedWidth: CGFloat = 68
    /// The gap between the panel and the screen edges.
    static let margin: CGFloat = 14

    @Binding var selection: Section
    @Binding var expanded: Bool
    /// The active profile, or nil while profiles are off (no avatar row then).
    let profile: ProfileDTO?
    let onSettings: () -> Void
    let onProfile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let profile { profileRow(profile).padding(.bottom, Theme.Space.xs) }
            row(.search)
            row(.home)
            groupHeader("Discover")
            row(.movies)
            row(.shows)
            groupHeader("Yours")
            row(.watchlist)
            row(.library)
            Spacer(minLength: Theme.Space.lg)
            bottomRow
        }
        .padding(.horizontal, expanded ? 12 : 10)
        .padding(.vertical, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(panel)
    }

    // MARK: Panel

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: expanded ? Theme.Radius.panel : Self.collapsedWidth / 2,
                         style: .continuous)
    }

    private var panel: some View {
        panelShape
            .fill(LinearGradient(colors: [Theme.Palette.panelTop, Theme.Palette.panelBottom],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(panelShape.strokeBorder(Theme.Palette.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 24, x: 4, y: 8)
    }

    // MARK: Rows

    private func row(_ section: Section) -> some View {
        let selected = section == selection
        return Button { selection = section } label: {
            rowLabel(title: section.title, systemImage: section.icon, selected: selected)
        }
        .buttonStyle(SidebarRowStyle())
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(section.title)
    }

    private func rowLabel(title: String, systemImage: String, selected: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 26)
            if expanded {
                Text(title)
                    .font(.system(size: 17, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize()                 // never squeezed while the panel animates
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(selected ? Theme.Palette.onFocus : Theme.Palette.textPrimary)
        .frame(height: 44)
        .padding(.horizontal, expanded ? 14 : 0)
        .frame(maxWidth: .infinity, alignment: expanded ? .leading : .center)
        .background {
            if selected { Capsule().fill(Theme.Palette.focus) }
        }
        .contentShape(Capsule())
    }

    /// "Discover" / "Yours" — a quiet label with a hairline running out to the panel's edge. A
    /// plain hairline while collapsed, so the groups still read as groups.
    private func groupHeader(_ title: String) -> some View {
        HStack(spacing: Theme.Space.sm) {
            if expanded {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize()
                    .transition(.opacity)
            }
            Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
        }
        .padding(.horizontal, expanded ? 14 : 8)
        .padding(.top, 18).padding(.bottom, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }

    private func profileRow(_ profile: ProfileDTO) -> some View {
        Button(action: onProfile) {
            HStack(spacing: 14) {
                ProfileAvatarImage(token: profile.avatar, diameter: 30, colorTag: profile.colorTag)
                if expanded {
                    Text(profile.name).font(.system(size: 17, weight: .medium)).lineLimit(1)
                        .fixedSize().transition(.opacity)
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(Theme.Palette.textPrimary)
            .frame(height: 48)
            .padding(.horizontal, expanded ? 12 : 0)
            .frame(maxWidth: .infinity, alignment: expanded ? .leading : .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowStyle())
        .accessibilityLabel("Switch profile")
    }

    /// Settings, pinned to the bottom, with the collapse toggle beside it (below it when collapsed).
    @ViewBuilder private var bottomRow: some View {
        let settings = Button(action: onSettings) {
            rowLabel(title: "Settings", systemImage: "gearshape", selected: false)
        }
        .buttonStyle(SidebarRowStyle())
        .accessibilityLabel("Settings")

        let toggle = Button {
            // Animated here, in the toggle's own transaction — the panel width and the page padding
            // move together, and nothing else on screen picks up the spring.
            withAnimation(Theme.Motion.standard) { expanded.toggle() }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowStyle())
        .accessibilityLabel(expanded ? "Collapse sidebar" : "Expand sidebar")

        if expanded {
            HStack(spacing: 0) { settings; toggle }
        } else {
            VStack(spacing: 2) { settings; toggle }
        }
    }
}

/// A sidebar row's press feedback: a quick dim, nothing that moves the layout.
private struct SidebarRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}
