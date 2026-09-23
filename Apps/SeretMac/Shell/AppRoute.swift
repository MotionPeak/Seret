import DebridCore

/// Everything a section can push. M2/M3 add .person(TMDBPersonRef), .genre(...), .search(...).
enum AppRoute: Hashable {
    case title(MediaItem)
}
