import DebridCore
import DebridUI
import SwiftUI

/// Where Browse gets its stores: a harness-injected instance wins (the same seam `titlePreview`
/// and friends already use elsewhere), otherwise `BrowseRoot` builds one from the session. A fresh
/// `GenreGridStore` is built through a closure rather than stored directly — a grid is a transient
/// drill-down (Decision: `AppSession.makeGenreGrid` is deliberately not cached).
struct BrowseSources {
    let movies: DiscoverStore?
    let shows: DiscoverStore?
    let makeGenreGrid: @MainActor (MediaKind, DiscoverStore.Genre) -> GenreGridStore?

    func discover(for kind: MediaKind) -> DiscoverStore? { kind == .movie ? movies : shows }
}

extension EnvironmentValues {
    @Entry var previewBrowse: BrowseSources? = nil
}
