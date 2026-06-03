import DebridCore
import SwiftUI

/// A scrolling grid of poster cards. tvOS's focus engine handles poster scaling + the ring.
struct PosterGrid: View {
    let items: [MediaItem]

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 50)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 50) {
                ForEach(items) { PosterCard(item: $0) }
            }
            .padding(60)
        }
    }
}
