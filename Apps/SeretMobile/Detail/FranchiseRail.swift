import DebridCore
import DebridUI
import SwiftUI

/// Every film in a franchise, in the order they came out, numbered. The one you are looking at is
/// ringed; tapping another opens its page.
///
/// Release order on purpose: a prequel that arrived fifth is shown fifth, because that is the order
/// a person watches a series in.
///
/// Like `SimilarRail`, this only *decides* — the Detail screen presents, because Detail is itself a
/// full-screen cover and cannot stack another from the same shell.
struct FranchiseRail: View {
    let franchise: Franchise
    let currentTmdbID: Int?
    /// Opens a film's page (owned item, or a placeholder for one you do not have).
    let onOpen: (MediaItem) -> Void
    /// The page's leading margin — the header sits on it and the row scrolls out to the edge.
    var margin: CGFloat = 0

    @Environment(AppSession.self) private var session
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            TitleSectionHeader(title: franchise.name).padding(.horizontal, margin)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: PosterTileMetrics.spacing) {
                    ForEach(Array(franchise.parts.enumerated()), id: \.element.id) { index, part in
                        tile(part, number: index + 1)
                    }
                }
                // Room for the current film's ring.
                .padding(.vertical, 2)
            }
            .contentMargins(.horizontal, margin, for: .scrollContent)
        }
        .task {
            ImageMemoryCache.prefetch(
                franchise.parts.compactMap { TMDBClient.imageURL(path: $0.posterPath, size: "w342") })
        }
    }

    private func tile(_ part: TMDBSearchResult, number: Int) -> some View {
        // Read live, so a film added while this page is open flips to "In Library" on next render.
        let owned = session.libraryStore?.ownedItem(tmdbID: part.id, kind: .movie)
        let isCurrent = part.id == currentTmdbID
        return Button {
            onOpen(owned ?? .placeholder(for: SearchHit(result: part, kind: .movie)))
        } label: {
            PosterTile(posterPath: part.posterPath, title: part.displayTitle,
                       width: PosterTileMetrics.width(hSize), owned: owned != nil)
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: PosterTileMetrics.corner, style: .continuous)
                            .strokeBorder(Theme.Palette.focus, lineWidth: 3)
                    }
                }
                .overlay(alignment: .topLeading) { numberBadge(number).padding(6) }
        }
        .pressable()
    }

    private func numberBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Theme.Palette.badgeBacking, in: Capsule())
    }
}
