import DebridCore
import DebridUI
import SwiftUI

/// A scrolling grid of poster cards. tvOS's focus engine handles poster scaling + the ring.
struct PosterGrid: View {
    let items: [MediaItem]
    /// Movie ids the active profile has finished — drives the ✓ badge + the menu toggle.
    var watchedMovieIDs: Set<String> = []
    var onRemove: (MediaItem) -> Void = { _ in }
    var onToggleWatched: (MediaItem) -> Void = { _ in }

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 50)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 50) {
                ForEach(items) { item in
                    PosterCard(item: item,
                               watched: item.kind == .movie && watchedMovieIDs.contains(item.id),
                               onRemove: onRemove,
                               onToggleWatched: onToggleWatched)
                }
            }
            .padding(60)
        }
    }
}
