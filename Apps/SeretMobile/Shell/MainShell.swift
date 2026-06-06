import DebridUI
import SwiftUI

/// The signed-in shell. Adapts to the horizontal size class: a tab bar on iPhone
/// (compact) and a `NavigationSplitView` sidebar on iPad (regular). Gold selection tint.
struct MainShell: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var sidebarSelection: Section? = .home

    var body: some View {
        if sizeClass == .compact {
            tabBar
        } else {
            splitView
        }
    }

    // MARK: iPhone — tab bar

    private var tabBar: some View {
        TabView {
            HomeScreen()
                .tabItem { Label(Section.home.title, systemImage: Section.home.icon) }
            sectionStack(.movies)
                .tabItem { Label(Section.movies.title, systemImage: Section.movies.icon) }
            sectionStack(.shows)
                .tabItem { Label(Section.shows.title, systemImage: Section.shows.icon) }
            NavigationStack { SettingsView() }
                .tabItem { Label(Section.settings.title, systemImage: Section.settings.icon) }
        }
        .tint(Theme.Palette.gold)
    }

    // MARK: iPad — split view

    private var splitView: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $sidebarSelection) { section in
                Label(section.title, systemImage: section.icon).tag(section)
            }
            .navigationTitle("Seret")
            .tint(Theme.Palette.gold)
        } detail: {
            switch sidebarSelection ?? .home {
            case .home: HomeScreen()
            case .movies: sectionStack(.movies)
            case .shows: sectionStack(.shows)
            case .settings: NavigationStack { SettingsView() }
            }
        }
        .tint(Theme.Palette.gold)
    }

    private func sectionStack(_ section: Section) -> some View {
        NavigationStack {
            LibrarySection(section: section)
                .navigationTitle(section.title)
        }
    }

    enum Section: Hashable, CaseIterable, Identifiable {
        case home, movies, shows, settings
        var id: Self { self }
        var title: String {
            switch self {
            case .home: "Home"
            case .movies: "Movies"
            case .shows: "Shows"
            case .settings: "Settings"
            }
        }
        var icon: String {
            switch self {
            case .home: "house"
            case .movies: "film"
            case .shows: "tv"
            case .settings: "gearshape"
            }
        }
    }
}
