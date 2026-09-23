import CoreGraphics

enum SidebarGroup: Equatable {
    case browse, yours
    var title: String { self == .browse ? "Browse" : "Yours" }
}

/// The main window's sections, in sidebar order. ⌘1…⌘5 follow this order.
enum SidebarSection: String, CaseIterable, Identifiable {
    case home, movies, shows, watchlist, library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .movies: "Movies"
        case .shows: "Shows"
        case .watchlist: "Watchlist"
        case .library: "My Library"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .movies: "film"
        case .shows: "tv"
        case .watchlist: "bookmark"
        case .library: "square.stack"
        }
    }

    var selectedSymbol: String { symbol + ".fill" }

    var group: SidebarGroup {
        switch self {
        case .home, .movies, .shows: .browse
        case .watchlist, .library: .yours
        }
    }

    var shortcutDigit: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
}

/// The floating sidebar's geometry, in points.
enum SidebarMetrics {
    static let expandedWidth: CGFloat = 250
    static let railWidth: CGFloat = 76
    /// Distance from the window's edges: the sidebar floats.
    static let inset: CGFloat = 10
    /// Space between the sidebar and the page content.
    static let gap: CGFloat = 14

    static func width(collapsed: Bool) -> CGFloat { collapsed ? railWidth : expandedWidth }
    static func contentLeading(collapsed: Bool) -> CGFloat { inset + width(collapsed: collapsed) + gap }
}
