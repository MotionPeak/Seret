import DebridCore
import DebridUI
import SwiftUI

/// One library title in a grid: the rail's `PosterTile` (ring and lift, the watched ✓ and dim) with
/// the title below it (`CaptionedPoster`), opening the title's page, with the library's
/// press-and-hold menu (mark watched, remove).
struct PosterCard: View {
    let item: MediaItem
    /// Finished — dims the poster + shows a ✓ badge, and flips the menu's toggle label.
    var watched: Bool = false
    let session: AppSession
    var onRemove: (MediaItem) -> Void = { _ in }
    /// Focus landed on this card — the grid's backdrop follows it.
    var onFocus: () -> Void = {}

    var body: some View {
        CaptionedPoster(caption: item.title) {
            PosterTile(posterPath: item.posterPath, title: item.title, watched: watched,
                       onFocus: onFocus, value: item)
                .libraryTitleMenu(for: item, session: session, onRemove: onRemove)
        }
    }
}
