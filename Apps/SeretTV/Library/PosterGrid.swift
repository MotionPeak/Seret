import DebridCore
import DebridUI
import SwiftUI

/// A scrolling grid of poster cards. tvOS's focus engine handles poster scaling + the ring.
struct PosterGrid: View {
    let items: [MediaItem]
    var onRemove: (MediaItem) -> Void = { _ in }

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 50)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 50) {
                ForEach(items) { PosterCard(item: $0, onRemove: onRemove) }
            }
            .padding(60)
        }
    }
}
