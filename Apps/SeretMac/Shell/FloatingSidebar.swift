import DebridUI
import SwiftUI

/// The Liquid Glass sidebar that floats over the full-bleed page (approved mockup 2). It collapses to
/// an icon rail — icons never move, labels fade and slide, section titles become hairlines — and the
/// gold selection pill glides between rows.
struct FloatingSidebar: View {
    @Bindable var model: ShellModel
    @Namespace private var selectionSpace
    @Environment(\.openSettings) private var openSettings

    private var collapsed: Bool { model.isSidebarCollapsed }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: SidebarMetrics.trafficLightsBand)   // the window's traffic lights sit here
            brand.padding(.bottom, 18)
            group(.browse)
            group(.yours).padding(.top, 6)
            Spacer(minLength: 12)
            SidebarRow(title: "Settings", symbol: "gearshape", selectedSymbol: "gearshape.fill",
                       isSelected: false, collapsed: collapsed, namespace: selectionSpace) { openSettings() }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(width: SidebarMetrics.width(collapsed: collapsed), alignment: .leading)
        .frame(maxHeight: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.sidebar, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        .padding(SidebarMetrics.inset)
        .animation(Theme.Motion.standard, value: collapsed)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Button { model.toggleSidebar() } label: {
                SeretMark().frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help(collapsed ? "Expand sidebar (⌃⌘S)" : "Collapse sidebar (⌃⌘S)")
            if !collapsed {
                Text("Seret").font(.system(size: 19, weight: .heavy))
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                Spacer()
                Button { model.toggleSidebar() } label: {
                    Image(systemName: "sidebar.left").font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Collapse sidebar (⌃⌘S)")
                .transition(.opacity)
            }
        }
        .padding(.leading, 15)
        .padding(.trailing, 8)
        .frame(height: 30)
    }

    /// One VStack, not a bare view builder: a modifier on a multi-view builder result applies to EVERY
    /// child, so `.padding(.top, 6)` on the group used to space out each of its rows.
    private func group(_ group: SidebarGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(group)
            ForEach(SidebarSection.allCases.filter { $0.group == group }) { section in
                SidebarRow(title: section.title, symbol: section.symbol, selectedSymbol: section.selectedSymbol,
                           isSelected: model.selection == section, collapsed: collapsed,
                           namespace: selectionSpace) {
                    withAnimation(Theme.Motion.standard) { model.select(section) }
                }
            }
        }
    }

    private func header(_ group: SidebarGroup) -> some View {
        ZStack(alignment: .leading) {
            if collapsed {
                Theme.Palette.hairline.frame(height: 1).padding(.horizontal, 14)
                    .transition(.opacity)
            } else {
                Text(group.title.uppercased())
                    .font(.system(size: 10.5, weight: .bold)).tracking(1.4)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .padding(.leading, 12)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
    }
}

/// One sidebar row: icon + label, a hover wash, and — when selected — the gliding gold pill.
private struct SidebarRow: View {
    let title: String
    let symbol: String
    let selectedSymbol: String
    let isSelected: Bool
    let collapsed: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: isSelected ? selectedSymbol : symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)
                    .shadow(color: isSelected ? Theme.Palette.gold.opacity(0.65) : .clear, radius: 6)
                if !collapsed {
                    Text(title).font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(isSelected ? Theme.Palette.gold : (hovering ? Theme.Palette.textPrimary : Color(hex: 0x9A9AA0)))
            .padding(.leading, 17)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.Palette.gold.opacity(0.24), Theme.Palette.gold.opacity(0.09)],
                                             startPoint: .leading, endPoint: .trailing))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Theme.Palette.gold.opacity(0.30), lineWidth: 1))
                        .shadow(color: Theme.Palette.gold.opacity(0.16), radius: 12)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(collapsed ? title : "")
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }
}
