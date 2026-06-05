import DebridUI
import SwiftUI

/// The signed-in shell. Adapts to the horizontal size class: a tab bar on iPhone
/// (compact) and a `NavigationSplitView` sidebar on iPad (regular). Movies/Shows are
/// stubs until 8b wires the real grids.
struct MainShell: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var sidebarSelection: Section? = .movies

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
            sectionStack(.movies)
                .tabItem { Label(Section.movies.title, systemImage: Section.movies.icon) }
            sectionStack(.shows)
                .tabItem { Label(Section.shows.title, systemImage: Section.shows.icon) }
            NavigationStack { SettingsView() }
                .tabItem { Label(Section.settings.title, systemImage: Section.settings.icon) }
        }
    }

    // MARK: iPad — split view

    private var splitView: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $sidebarSelection) { section in
                Label(section.title, systemImage: section.icon).tag(section)
            }
            .navigationTitle("Seret")
        } detail: {
            switch sidebarSelection ?? .movies {
            case .movies: sectionStack(.movies)
            case .shows: sectionStack(.shows)
            case .settings: NavigationStack { SettingsView() }
            }
        }
    }

    private func sectionStack(_ section: Section) -> some View {
        NavigationStack {
            LibrarySection(section: section)
                .navigationTitle(section.title)
        }
    }

    enum Section: Hashable, CaseIterable, Identifiable {
        case movies, shows, settings
        var id: Self { self }
        var title: String {
            switch self {
            case .movies: "Movies"
            case .shows: "Shows"
            case .settings: "Settings"
            }
        }
        var icon: String {
            switch self {
            case .movies: "film"
            case .shows: "tv"
            case .settings: "gearshape"
            }
        }
    }
}
