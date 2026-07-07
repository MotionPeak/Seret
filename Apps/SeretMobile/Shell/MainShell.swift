import DebridCore
import DebridUI
import SwiftUI

/// The signed-in shell. Adapts to the horizontal size class: a tab bar on iPhone
/// (compact) and a custom Gold Glass sidebar (`NavigationSplitView`) on iPad (regular).
/// Movies / TV are **browse** surfaces; My Library holds the user's Real-Debrid content.
struct MainShell: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var showingProfiles = false
    @State private var showingSettings = false
    /// Persisted across launches. Collapsed shows an icon-only rail; expanded shows labels.
    @AppStorage("seret.ipad.sidebarExpanded") private var sidebarExpanded = true

    private let railExpandedWidth: CGFloat = 248
    private let railCollapsedWidth: CGFloat = 76

    var body: some View {
        Group {
            if sizeClass == .compact {
                tabBar
            } else {
                splitView
            }
        }
        .fullScreenCover(isPresented: $showingProfiles) {
            WhoIsWatchingScreen(onPicked: { showingProfiles = false }).environment(session)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .environment(session)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingSettings = false }.tint(Theme.Palette.gold)
                        }
                    }
            }
        }
    }

    // MARK: iPhone — tab bar

    private var tabBar: some View {
        TabView(selection: Binding(get: { router.selectedSection }, set: { router.selectedSection = $0 })) {
            ForEach(Section.allCases) { section in
                screen(for: section)
                    .tabItem { Label(section.title, systemImage: section.icon) }
                    .tag(section)
            }
        }
        .tint(Theme.Palette.gold)
    }

    // MARK: iPad — custom collapsible rail

    /// A bespoke split: a collapsible Gold Glass rail beside the detail screen.
    /// Collapsing animates the rail down to an icon-only strip — the icons stay
    /// pressable — instead of hiding the sidebar entirely.
    private var splitView: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarExpanded ? railExpandedWidth : railCollapsedWidth)
            Rectangle()
                .fill(Theme.Palette.hairline)
                .frame(width: 1)
                .ignoresSafeArea()
            screen(for: router.selectedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(Theme.Palette.gold)
    }

    @ViewBuilder private func screen(for section: Section) -> some View {
        switch section {
        case .home:    HomeScreen()
        case .find:    NavigationStack { FindScreen() }
        case .library: NavigationStack { MyLibraryScreen() }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            header
                .padding(.horizontal, Theme.Space.sm)
                .padding(.top, Theme.Space.sm).padding(.bottom, Theme.Space.lg)

            ForEach(Section.allCases) { section in
                sidebarRow(section)
            }
            Spacer()
            settingsRow
            profileRow
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.surface1.opacity(0.6))
        .background(Theme.Palette.canvas)
    }

    /// Header IS the toggle: tapping the Seret play-mark expands/collapses the rail; the
    /// "Seret" wordmark slides + fades in/out as part of the animation. No separate chevron.
    private var header: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { sidebarExpanded.toggle() }
        } label: {
            HStack(spacing: Theme.Space.sm) {
                SeretMark().frame(width: 30, height: 30)
                if sidebarExpanded {
                    Text("Seret").font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .fixedSize()                     // never compress while the rail collapses
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal:   .move(edge: .leading).combined(with: .opacity)))
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: sidebarExpanded ? .leading : .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sidebarExpanded ? "Collapse sidebar" : "Expand sidebar")
    }

    /// Settings sits just above the profile chip at the bottom of the rail — tucked to the side,
    /// never a primary nav row.
    private var settingsRow: some View {
        Button { showingSettings = true } label: {
            HStack(spacing: Theme.Space.md) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 26)
                if sidebarExpanded {
                    Text("Settings").font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.vertical, Theme.Space.md)
            .padding(.horizontal, sidebarExpanded ? Theme.Space.md : 0)
            .frame(maxWidth: .infinity, alignment: sidebarExpanded ? .leading : .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    private var activeProfile: ProfileDTO? { session.activeProfiles?.activeProfile }

    /// Bottom-of-sidebar profile chip — the active avatar; tap to switch profiles.
    private var profileRow: some View {
        Button { showingProfiles = true } label: {
            HStack(spacing: Theme.Space.md) {
                ProfileAvatarImage(token: activeProfile?.avatar ?? "", diameter: 30,
                                   colorTag: activeProfile?.colorTag ?? "gold")
                if sidebarExpanded {
                    Text(activeProfile?.name ?? "Profile")
                        .font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.vertical, Theme.Space.md)
            .padding(.horizontal, sidebarExpanded ? Theme.Space.md : 0)
            .frame(maxWidth: .infinity, alignment: sidebarExpanded ? .leading : .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch profile")
    }

    private func sidebarRow(_ section: Section) -> some View {
        let selected = section == router.selectedSection
        return Button { router.selectedSection = section } label: {
            HStack(spacing: Theme.Space.md) {
                Image(systemName: selected ? section.filledIcon : section.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 26)
                if sidebarExpanded {
                    Text(section.title).font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(selected ? Theme.Palette.gold : Theme.Palette.textSecondary)
            .padding(.vertical, Theme.Space.md)
            .padding(.horizontal, sidebarExpanded ? Theme.Space.md : 0)
            .frame(maxWidth: .infinity, alignment: sidebarExpanded ? .leading : .center)
            .background(selected ? Theme.Palette.gold.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .help(section.title)
    }

    enum Section: Hashable, CaseIterable, Identifiable {
        case home, find, library
        var id: Self { self }
        var title: String {
            switch self {
            case .home: "Home"
            case .find: "Find"
            case .library: "My Library"
            }
        }
        var icon: String {
            switch self {
            case .home: "house"
            case .find: "magnifyingglass"
            case .library: "rectangle.stack"
            }
        }
        var filledIcon: String {
            switch self {
            case .home: "house.fill"
            case .find: "magnifyingglass"
            case .library: "rectangle.stack.fill"
            }
        }
    }
}
