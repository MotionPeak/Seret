import DebridCore
import DebridUI
import SwiftUI

/// A scrolling grid of poster cards. tvOS's focus engine handles poster scaling + the ring.
struct PosterGrid: View {
    let items: [MediaItem]
    /// Ids the active profile has finished — drives the ✓ badge + the menu toggle. Shows included:
    /// a series hangs off its own key, the one `ShowWatchMarker` writes.
    var watchedIDs: Set<String> = []
    let session: AppSession
    var onRemove: (MediaItem) -> Void = { _ in }

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 50)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 50) {
                ForEach(items) { item in
                    PosterCard(item: item,
                               watched: watchedIDs.contains(item.id),
                               session: session,
                               onRemove: onRemove)
                }
            }
            .padding(60)
        }
        .gridTopFade()
    }
}
