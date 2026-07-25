import DebridCore
import DebridUI
import SwiftUI

/// A horizontal rail of TMDB-suggested titles, shown at the bottom of the Movie/Show Detail page.
///
/// Each poster is a `BrowseTile`, so a similar title routes exactly the way the same title would
/// from Browse or Search — owned pushes the library Detail, not-owned opens the Add flow — and
/// carries the same "In Library" checkmark. Reusing the tile also inherits its focus discipline:
/// ONE stable `NavigationLink` whose *value* varies, never an owned/not-owned branch of two links
/// (a branch swap destroys the focused tile and tvOS silently drops focus elsewhere).
///
/// TMDB's `/similar` is namespaced per media type, so a movie's suggestions are movies and a
/// show's are shows — hence `parentKind` rather than a per-result kind.
struct SimilarRail: View {
    let titles: [TMDBSearchResult]
    let parentKind: MediaKind

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("More Like This").sectionTitle()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 36) {
                    ForEach(titles) { title in
                        BrowseTile(hit: SearchHit(result: title, kind: parentKind))
                    }
                }
                .padding(.horizontal, Theme.Layout.contentMargin)
                .padding(.vertical, 12)   // headroom so the focus scale isn't clipped top/bottom
            }
            // Runs edge-to-edge (negating the page's 60pt inset) so a focused card at either end
            // isn't clipped when it scales up.
            .padding(.horizontal, -Theme.Layout.contentMargin)
        }
        .focusSection()
        .task {
            ImageMemoryCache.prefetch(
                titles.compactMap { TMDBClient.imageURL(path: $0.posterPath, size: "w500") })
        }
    }
}
