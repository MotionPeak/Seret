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
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // Lazy: `similar` is a whole TMDB page, so a non-lazy row fetched and decoded ~20 posters
        // the moment the page appeared, however few were on screen.
        PlexRail(title: "More Like This", id: "detail-similar") {
            ForEach(titles) { title in
                BrowseTile(hit: SearchHit(result: title, kind: parentKind))
            }
        }
        .task {
            // Warmed at the size the tiles decode for, or the warm-up fills a cache entry no tile reads.
            ImageMemoryCache.prefetch(
                titles.compactMap { TMDBClient.imageURL(path: $0.posterPath, size: "w500") },
                target: ImageDownsampling.targetPixels(points: PosterTileMetrics.decodeSize, scale: displayScale))
        }
    }
}
