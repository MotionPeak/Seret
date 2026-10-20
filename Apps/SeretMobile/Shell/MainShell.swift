import DebridCore
import DebridUI
import SwiftUI
import UIKit

/// The signed-in shell. Adapts to the horizontal size class:
///
/// - **iPhone (compact)** — the system `TabView`: Home · Movies · Shows · Watchlist · Library. On
///   iOS 26 that IS the floating Liquid Glass tab bar; iOS 18 gets the standard bar restyled to
///   the neutral palette (`styleLegacyTabBar`). Search and Settings are glass circles on Home's own
///   header, and Search is on the Movies / Shows headers too.
/// - **iPad (regular)** — the Plex-style floating sidebar (`ShellSidebar`) over the page, which
///   runs full-bleed underneath it so backdrop art shows past the panel.
///
/// The selected section lives on `AppRouter`, above this view, so it survives a size-class flip.
struct MainShell: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var showingProfiles = false
    @State private var showingSettings = false
    /// Persisted across launches. Collapsed shows an icon-only capsule; expanded shows labels.
    @AppStorage("seret.ipad.sidebarExpanded") private var sidebarExpanded = true
    /// The section, restored when the system relaunches the scene.
    @SceneStorage("seret.mobile.section") private var storedSection = Section.home.rawValue
    @State private var restoredSection = false

    var body: some View {
        Group {
            if sizeClass == .compact {
                tabBar
            } else {
                sidebarLayout
            }
        }
        .tint(Theme.Palette.focus)
        .onAppear {
            // Once per shell, and only over the default: a later re-appearance must not drag the
            // viewer back to a stale tab, and a section someone already chose wins.
            guard !restoredSection else { return }
            restoredSection = true
            if router.selectedSection == .home, let restored = Section(rawValue: storedSection) {
                router.selectedSection = restored
            }
        }
        .onChange(of: router.selectedSection) { _, section in storedSection = section.rawValue }
        .fullScreenCover(isPresented: $showingProfiles) {
            WhoIsWatchingScreen(onPicked: { showingProfiles = false }).environment(session)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .environment(session)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingSettings = false }.tint(Theme.Palette.focus)
                        }
                    }
            }
        }
    }

    // MARK: iPhone — tab bar

    /// Search is a sidebar row, not a tab: crossing from iPad to iPhone with it selected lands on
    /// Home, where the search circle is.
    private var tabSelection: Binding<Section> {
        Binding(get: { router.selectedSection.isTab ? router.selectedSection : .home },
                set: { router.selectedSection = $0 })
    }

    private var tabBar: some View {
        TabView(selection: tabSelection) {
            ForEach(Section.tabs) { section in
                Tab(section.title, systemImage: section.icon, value: section) {
                    screen(for: section)
                }
            }
        }
        .onAppear(perform: Self.styleLegacyTabBar)
    }

    /// iOS 18 only: the standard bar, translucent over the canvas, white when selected. iOS 26's
    /// Liquid Glass bar is left exactly as the system draws it — an appearance object would flatten
    /// it back into a plain bar.
    static func styleLegacyTabBar() {
        if #available(iOS 26, *) { return }
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.backgroundColor = UIColor(Theme.Palette.canvas.opacity(0.45))
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.12)
        let item = UITabBarItemAppearance()
        let rest = UIColor(Theme.Palette.textSecondary)
        item.normal.iconColor = rest
        item.normal.titleTextAttributes = [.foregroundColor: rest]
        item.selected.iconColor = .white
        item.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    // MARK: iPad — floating sidebar

    private var sidebarLayout: some View {
        let width = sidebarExpanded ? ShellSidebar.expandedWidth : ShellSidebar.collapsedWidth
        let inset = width + ShellSidebar.margin
        return ZStack(alignment: .topLeading) {
            CanvasBackground()
            screen(for: router.selectedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The page lays out beside the panel. Padding, not a leading safe-area inset: a
                // NavigationStack does not hand a leading inset on to its pages (measured — titles
                // and spinners sat under the panel). A page that wants its art to run on under the
                // panel, as the mockup's Home does, reads `shellLeadingInset` and bleeds by it.
                .padding(.leading, inset)
                .environment(\.shellLeadingInset, inset)
            ShellSidebar(selection: Binding(get: { router.selectedSection },
                                            set: { router.selectedSection = $0 }),
                         expanded: $sidebarExpanded,
                         profile: ProfilesFeature.isEnabled ? session.activeProfiles?.activeProfile : nil,
                         onSettings: { showingSettings = true },
                         onProfile: { showingProfiles = true })
                .frame(width: width)
                .padding(ShellSidebar.margin)
        }
        .animation(Theme.Motion.standard, value: sidebarExpanded)
    }

    @ViewBuilder private func screen(for section: Section) -> some View {
        switch section {
        case .home:      HomeScreen()
        case .movies:    NavigationStack { FindScreen(mode: .browse, kind: .movie) }
        case .shows:     NavigationStack { FindScreen(mode: .browse, kind: .show) }
        case .watchlist: NavigationStack { WatchlistScreen() }
        case .library:   NavigationStack { MyLibraryScreen() }
        case .search:    NavigationStack { FindScreen(mode: .search) }
        }
    }

    enum Section: String, Hashable, CaseIterable, Identifiable {
        case home, movies, shows, watchlist, library, search
        var id: Self { self }

        /// The iPhone tab bar, in order. Search is reached from the page headers instead.
        static let tabs: [Section] = [.home, .movies, .shows, .watchlist, .library]
        var isTab: Bool { Self.tabs.contains(self) }

        var title: String {
            switch self {
            case .home: "Home"
            case .movies: "Movies"
            case .shows: "Shows"
            case .watchlist: "Watchlist"
            case .library: "Library"
            case .search: "Search"
            }
        }
        var icon: String {
            switch self {
            case .home: "house"
            case .movies: "film"
            case .shows: "tv"
            case .watchlist: "bookmark"
            case .library: "books.vertical"
            case .search: "magnifyingglass"
            }
        }
    }
}

extension EnvironmentValues {
    /// How far the iPad sidebar covers the page's leading edge (0 on iPhone). A page draws its
    /// backdrop out by this much to run it on under the floating panel.
    @Entry var shellLeadingInset: CGFloat = 0
}
