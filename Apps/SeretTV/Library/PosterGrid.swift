import DebridCore
import DebridUI
import SwiftUI

/// A grid of library poster cards (`PosterGridLayout`, a root page's inset) — not scrolling itself:
/// `LibraryScreen` scrolls it together with the Downloading strip above it. Each card reports focus
/// through `onFocus`, which drives the page's backdrop.
struct PosterGrid: View {
    let items: [MediaItem]
    /// Ids the active profile has finished — drives the ✓ badge + the menu toggle. Shows included:
    /// a series hangs off its own key, the one `ShowWatchMarker` writes.
    var watchedIDs: Set<String> = []
    let session: AppSession
    var onRemove: (MediaItem) -> Void = { _ in }
    var onFocus: (MediaItem) -> Void = { _ in }
    /// Focus arrived at (true) or left (false) the card with this id.
    var onFocusChange: (String, Bool) -> Void = { _, _ in }

    var body: some View {
        LazyVGrid(columns: PosterGridLayout.columns, spacing: PosterGridLayout.rowSpacing) {
            ForEach(items) { item in
                PosterCard(item: item,
                           watched: watchedIDs.contains(item.id),
                           session: session,
                           onRemove: onRemove,
                           onFocus: { onFocus(item) },
                           onFocusChange: { onFocusChange(item.id, $0) })
            }
        }
        .padding(.horizontal, PosterGridLayout.rootInset)
        .padding(.vertical, PosterGridLayout.topPadding)
    }
}
