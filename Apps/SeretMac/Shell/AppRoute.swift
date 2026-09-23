import DebridCore

/// Everything a section can push. M3 adds .person(TMDBPersonRef).
enum AppRoute: Hashable {
    case title(MediaItem)
    /// The search results page — one per section, pushed by `ShellModel.setSearchQuery`.
    case search
}
