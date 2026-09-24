import DebridCore

/// Everything a section can push.
enum AppRoute: Hashable {
    case title(MediaItem)
    /// An actor or director, opened from a cast card or a credit name.
    case person(TMDBPersonRef)
}
