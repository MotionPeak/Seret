import DebridCore
import DebridUI
import SwiftUI

/// A horizontal rail of TMDB-suggested titles at the bottom of Movie/Show Detail.
///
/// A tap routes the same way the same poster routes from Find — owned opens that title's Detail,
/// not-owned opens the Add flow — but the rail only *decides*; the Detail screen presents. Detail
/// is itself a full-screen cover owned by the app shell, and a cover can't stack a second cover
/// from that same shell (the presentation is silently ignored), so routing through `AppRouter`
/// from in here does nothing. Hence the two closures.
///
/// TMDB's recommendations are namespaced per media type, so a movie's suggestions are movies and a
/// show's are shows — hence `parentKind` rather than a per-result kind.
struct SimilarRail: View {
    let titles: [TMDBSearchResult]
    let parentKind: MediaKind
    /// Already in the library → open its Detail.
    let onOpenOwned: (MediaItem) -> Void
    /// Not in the library → open the Add flow for it.
    let onAddNew: (SearchHit) -> Void
    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("MORE LIKE THIS")
                .font(Theme.Typo.label()).tracking(1.5).foregroundStyle(Theme.Palette.gold)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    ForEach(titles) { tile($0) }
                }
            }
        }
        .task {
            ImageMemoryCache.prefetch(
                titles.compactMap { TMDBClient.imageURL(path: $0.posterPath, size: "w342") })
        }
    }

    private func tile(_ title: TMDBSearchResult) -> some View {
        // Read live, so a title added while this page is open flips to "In Library" on next render.
        let owned = session.libraryStore?.ownedItem(tmdbID: title.id)
        return Button {
            if let owned { onOpenOwned(owned) }
            else { onAddNew(SearchHit(result: title, kind: parentKind)) }
        } label: {
            PosterCard(title: title.displayTitle,
                       posterURL: TMDBClient.imageURL(path: title.posterPath, size: "w342"))
                .overlay(alignment: .topTrailing) {
                    if owned != nil { inLibraryBadge.padding(6) }
                }
        }
        .pressable()
    }

    private var inLibraryBadge: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Color(hex: 0x1A1400), Theme.Palette.gold)
            .background(Circle().fill(.black.opacity(0.35)))
            .accessibilityLabel("In Library")
    }
}
