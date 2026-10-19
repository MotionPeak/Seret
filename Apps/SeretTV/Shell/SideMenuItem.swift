import SwiftUI

/// A row in the side menu. `profile` opens the profile picker, `search` pushes a destination, and
/// every other case selects a page.
///
/// `profile` is a case rather than a loose view so it shares the menu's `@FocusState` — otherwise
/// focusing the avatar leaves the menu collapsed, which is exactly the bug the first screenshot of
/// this view caught.
enum SideMenuItem: String, CaseIterable, Identifiable {
    case profile, search, home, movies, shows, watchlist, library, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile:  return "Profile"   // the shell substitutes the live profile name
        case .search:   return "Search"
        case .home:     return "Home"
        case .movies:   return "Movies"
        case .shows:    return "Shows"
        case .watchlist: return "Watchlist"
        case .library:  return "Library"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .profile:  return "person.crop.circle"   // unused — the row renders the avatar
        case .search:   return "magnifyingglass"
        case .home:     return "house"
        case .movies:   return "film"
        case .shows:    return "tv"
        case .watchlist: return "bookmark"
        case .library:  return "rectangle.stack"
        case .settings: return "gearshape"
        }
    }

    /// Rows rendered as a group under the profile. `settings` is pinned to the bottom separately.
    static let mainRows: [SideMenuItem] = [.search, .home, .movies, .shows, .watchlist, .library]

    /// A titled group of rows in the expanded panel. Collapsed, the headers take no height, so the
    /// capsule is just the icons.
    enum Section: CaseIterable {
        case discover, yours

        var title: String {
            switch self {
            case .discover: return "Discover"
            case .yours:    return "Yours"
            }
        }
    }

    /// The panel group this row belongs to; `nil` for rows that sit above or outside the groups.
    var section: Section? {
        switch self {
        case .movies, .shows:      return .discover
        case .watchlist, .library: return .yours
        default:                   return nil
        }
    }

    /// The section whose header is drawn directly above this row — set only on the FIRST main row
    /// of each section, so every header appears once.
    var startsSection: Section? {
        guard let section, let index = Self.mainRows.firstIndex(of: self) else { return nil }
        return index == 0 || Self.mainRows[index - 1].section != section ? section : nil
    }

    /// Whether selecting this row switches the page (as opposed to pushing or presenting).
    var isPage: Bool { self != .search && self != .profile }
}
