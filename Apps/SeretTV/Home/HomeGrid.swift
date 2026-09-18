import DebridCore
import DebridUI
import SwiftUI

/// A titled full-width grid — the vertical counterpart to `HomeRail`.
///
/// Recently Added is the one Home section you browse rather than glance at, and as a rail it
/// showed six titles at a time behind an indefinite number of right-presses while leaving the
/// bottom two-thirds of the screen empty. A grid spends the page it is already occupying.
///
/// Column metrics are `PosterGrid`'s, deliberately: a poster is then the same size on Home as it
/// is in My Library — six across at 1080p — so nothing re-scales crossing between the two.
struct HomeGrid<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 50)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).sectionTitle().padding(.leading, Theme.Layout.contentMargin)
            LazyVGrid(columns: columns, spacing: 50) {
                content
            }
            .padding(.horizontal, Theme.Layout.contentMargin)
            // Room for the focus lift at the first row's top edge and the last row's bottom.
            .padding(.vertical, 20)
        }
        // One target for vertical travel arriving from the rails above, and — like the rails — only
        // a target at all if its frame intersects the direction of travel, hence the full width.
        .focusSection()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
