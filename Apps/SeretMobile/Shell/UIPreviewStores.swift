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
    /// `-uiPreview homescript`: drives Home's stack and scroll on a timer.
    var homeScript: HomePreviewScript?
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
