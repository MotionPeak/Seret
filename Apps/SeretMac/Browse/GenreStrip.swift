import DebridCore
import DebridUI
import SwiftUI

/// The pill strip atop Movies/Shows: **All** then the kind's genres, in a horizontal scroll clear
/// of the sidebar. A genre is an in-place filter, not a route — clicking one just commits the
/// selection to `ShellModel`, and the caller swaps what's below.
struct GenreStrip: View {
    let kind: MediaKind
    let selected: DiscoverStore.Genre?
    let onSelect: (DiscoverStore.Genre?) -> Void

    @Environment(\.pageLeadingInset) private var pageLeadingInset

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button("All") { onSelect(nil) }
                    .buttonStyle(PillButtonStyle(selected: selected == nil))
                ForEach(DiscoverStore.genres(for: kind)) { genre in
                    Button(genre.name) { onSelect(genre) }
                        .buttonStyle(PillButtonStyle(selected: selected == genre))
                }
            }
            .padding(.vertical, 12)
        }
        .contentMargins(.leading, pageLeadingInset, for: .scrollContent)
        .contentMargins(.trailing, 28, for: .scrollContent)
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
    }
}
