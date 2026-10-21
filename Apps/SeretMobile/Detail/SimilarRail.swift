import DebridCore
import DebridUI
import SwiftUI

/// A horizontal rail of TMDB-suggested titles at the bottom of Movie/Show Detail.
///
/// A tap opens the title's page, exactly as the same poster does from Find: the library's item when
/// it is owned, a placeholder page — the unified title page, Play and all — when it is not. Not-owned
/// used to open the bare Versions list instead, and for a SHOW that list needs an episode to search
/// for, so every unowned show here dead-ended in "Couldn't load versions".
///
/// The rail only *decides*; the Detail screen presents. Detail is itself a full-screen cover owned
/// by the app shell, and a cover can't stack a second cover from that same shell (the presentation
/// is silently ignored), so routing through `AppRouter` from in here does nothing. Hence the
/// closure.
///
/// TMDB's recommendations are namespaced per media type, so a movie's suggestions are movies and a
/// show's are shows — hence `parentKind` rather than a per-result kind.
struct SimilarRail: View {
    let titles: [TMDBSearchResult]
    let parentKind: MediaKind
    /// Open this title's page.
    let onOpen: (MediaItem) -> Void
    /// The page's leading margin — the header sits on it and the row scrolls out to the edge.
    var margin: CGFloat = 0
    @Environment(AppSession.self) private var session
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            TitleSectionHeader(title: "More Like This").padding(.horizontal, margin)
            ScrollView(.horizontal, showsIndicators: false) {
                // Lazy: `similar` is a whole TMDB page, and a non-lazy row built and image-loaded
                // every one of them the moment the page appeared, however few were on screen.
                LazyHStack(alignment: .top, spacing: PosterTileMetrics.spacing) {
                    ForEach(titles) { tile($0) }
                }
            }
            .contentMargins(.horizontal, margin, for: .scrollContent)
        }
        .task {
            ImageMemoryCache.prefetch(
                titles.compactMap { TMDBClient.imageURL(path: $0.posterPath, size: "w342") })
        }
    }

    private func tile(_ title: TMDBSearchResult) -> some View {
        // Read live, so a title added while this page is open flips to "In Library" on next render.
        let owned = session.libraryStore?.ownedItem(tmdbID: title.id, kind: parentKind)
        return Button {
            onOpen(owned ?? .placeholder(for: SearchHit(result: title, kind: parentKind)))
        } label: {
            PosterTile(posterPath: title.posterPath, title: title.displayTitle,
                       width: PosterTileMetrics.width(hSize), owned: owned != nil)
        }
        .pressable()
    }
}
