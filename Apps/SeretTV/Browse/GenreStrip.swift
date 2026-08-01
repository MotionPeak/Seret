import DebridCore
import DebridUI
import SwiftUI

/// The horizontally scrolling genre selector at the top of Movies/Shows. `All` keeps the segment
/// rails; any other pill swaps the page for that genre's grid.
///
/// Commit-on-press, like every other pill row in the app: focusing a genre only highlights it. A
/// switch-on-focus row here would fire a TMDB request on every glide of the remote.
struct GenreStrip: View {
    let kind: MediaKind
    /// nil = "All".
    @Binding var selection: DiscoverStore.Genre?

    @FocusState private var focused: Int?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                Button("All") { selection = nil }
                    .buttonStyle(SeretPillStyle(selected: selection == nil))
                    .focused($focused, equals: 0)
                ForEach(DiscoverStore.genres(for: kind)) { genre in
                    Button(genre.name) { selection = genre }
                        .buttonStyle(SeretPillStyle(selected: selection == genre))
                        .focused($focused, equals: genre.tmdbID)
                }
            }
            // Run edge-to-edge (negate the page margin, re-pad the content) so a focused, scaled
            // pill is not clipped at the row edge.
            .padding(.horizontal, Theme.Layout.contentMargin)
            .padding(.vertical, 12)
        }
        .scrollClipDisabled()
        .padding(.horizontal, -Theme.Layout.contentMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }
}
