import DebridCore
import DebridUI
import SwiftUI

/// The signed-in shell. Adapts to the horizontal size class: a tab bar on iPhone
/// (compact) and a custom Gold Glass sidebar (`NavigationSplitView`) on iPad (regular).
/// Movies / TV are **browse** surfaces; My Library holds the user's Real-Debrid content.
struct MainShell: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var sidebarSelection: Section = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

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
            ForEach(Section.allCases) { section in
                screen(for: section)
                    .tabItem { Label(section.title, systemImage: section.icon) }
            }
        }
        .tint(Theme.Palette.gold)
    }

    // MARK: iPad — custom sidebar

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            screen(for: sidebarSelection)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Theme.Palette.gold)
    }

    @ViewBuilder private func screen(for section: Section) -> some View {
        switch section {
        case .home:    HomeScreen()
        case .movies:  NavigationStack { BrowseScreen(kind: .movie) }
        case .tv:      NavigationStack { BrowseScreen(kind: .show) }
        case .library: NavigationStack { MyLibraryScreen() }
        case .settings: NavigationStack { SettingsView() }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.sm) {
                SeretMark().frame(width: 26)
                Text("Seret").font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.top, Theme.Space.sm).padding(.bottom, Theme.Space.lg)

            ForEach(Section.allCases) { section in
                let selected = section == sidebarSelection
                Button { sidebarSelection = section } label: {
                    HStack(spacing: Theme.Space.md) {
                        Image(systemName: selected ? section.filledIcon : section.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 26)
                        Text(section.title).font(.system(size: 17, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(selected ? Theme.Palette.gold : Theme.Palette.textSecondary)
                    .padding(.vertical, Theme.Space.md).padding(.horizontal, Theme.Space.md)
                    .background(selected ? Theme.Palette.gold.opacity(0.14) : .clear,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.surface1.opacity(0.6))
        .background(Theme.Palette.canvas)
        .scrollContentBackground(.hidden)
    }

    enum Section: Hashable, CaseIterable, Identifiable {
        case home, movies, tv, library, settings
        var id: Self { self }
        var title: String {
            switch self {
            case .home: "Home"
            case .movies: "Movies"
            case .tv: "TV Shows"
            case .library: "My Library"
            case .settings: "Settings"
            }
        }
        var icon: String {
            switch self {
            case .home: "house"
            case .movies: "film"
            case .tv: "tv"
            case .library: "rectangle.stack"
            case .settings: "gearshape"
            }
        }
        var filledIcon: String {
            switch self {
            case .home: "house.fill"
            case .movies: "film.fill"
            case .tv: "tv.fill"
            case .library: "rectangle.stack.fill"
            case .settings: "gearshape.fill"
            }
        }
    }
}
