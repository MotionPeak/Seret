#if DEBUG
import DebridCore
import DebridUI
import SwiftUI

/// DEBUG only: fixture stores a `-uiPreview` harness hands the REAL pages (through the real shell)
/// in place of the session's, which a never-signed-in harness session does not have. Each page
/// reads its store as `preview?.x ?? session.x`, so outside a harness nothing changes.
struct UIPreviewStores {
    var home: HomeStore?
    var art: TitleArtStore?
    var downloads: [DownloadTile]?
    var moviesBrowse: DiscoverStore?
    var showsBrowse: DiscoverStore?
    var genreBrowsing: GenreBrowsing?
    /// `-uiPreview search…`: the search store (real TMDB search) and a query typed in at once.
    var search: SearchStore?
    var searchQuery: String?
    /// `-uiPreview library`: the library page's store, over `PagesFixture`'s titles.
    var library: LibraryStore?
    /// `-uiPreview homescript`: drives Home's stack and scroll on a timer.
    var homeScript: HomePreviewScript?
    /// `-uiPreview watchlist…`: the fixture list, its details, and whether Letterboxd counts as
    /// set up (non-nil makes the Watchlist page read these instead of the session's).
    var watchlist: WatchlistModel?
    var watchlistDetails: WatchlistDetailsStore?
    var watchlistConnected: Bool?
    /// Where the spin's winner art comes from (the unsigned harness session has no details).
    var watchlistArt: MediaDetailsProviding?
    /// `watchlistremove` / `watchlistremoved` / `spin`: what the page does by itself once shown.
    var watchlistScript: WatchlistPreviewScript?
}

/// What a Watchlist harness does without a finger (the iPad simulator cannot be tapped here):
/// open the removal confirmation for a film, confirm a removal through the fixture model (which
/// writes nowhere), or run Surprise Me.
struct WatchlistPreviewScript {
    var confirmRemovalOf: String?
    var removeSlug: String?
    var spins = false
}

/// Requests a harness makes of Home: bump `pushes` / `pops` to push See All or pop it, set
/// `scrollTo` to a rail id to scroll there.
@MainActor
@Observable
final class HomePreviewScript {
    var pushes = 0
    var pops = 0
    var scrollTo: String?
}

extension EnvironmentValues {
    @Entry var uiPreviewStores: UIPreviewStores?
}
#endif
