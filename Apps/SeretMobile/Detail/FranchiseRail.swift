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

    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(franchise.name.uppercased())
                .font(Theme.Typo.label()).tracking(1.5).foregroundStyle(Theme.Palette.gold)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    ForEach(Array(franchise.parts.enumerated()), id: \.element.id) { index, part in
                        tile(part, number: index + 1)
                    }
                }
            }
        }
        .task {
            ImageMemoryCache.prefetch(
                franchise.parts.compactMap { TMDBClient.imageURL(path: $0.posterPath, size: "w342") })
        }
    }

    private func tile(_ part: TMDBSearchResult, number: Int) -> some View {
        // Read live, so a film added while this page is open flips to "In Library" on next render.
        let owned = session.libraryStore?.ownedItem(tmdbID: part.id)
        let isCurrent = part.id == currentTmdbID
        return Button {
            onOpen(owned ?? .placeholder(for: SearchHit(result: part, kind: .movie)))
        } label: {
            PosterCard(title: part.displayTitle,
                       posterURL: TMDBClient.imageURL(path: part.posterPath, size: "w342"))
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(Theme.Palette.gold, lineWidth: 3)
                    }
                }
                .overlay(alignment: .topLeading) { numberBadge(number).padding(5) }
                .overlay(alignment: .topTrailing) {
                    if owned != nil { inLibraryBadge.padding(6) }
                }
        }
        .pressable()
    }

    private func numberBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.black.opacity(0.65), in: Capsule())
    }

    private var inLibraryBadge: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Theme.Palette.onGold, Theme.Palette.gold)
            .background(Circle().fill(.black.opacity(0.35)))
            .accessibilityLabel("In Library")
    }
}
