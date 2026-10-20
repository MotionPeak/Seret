import DebridCore
import DebridUI
import SwiftUI

/// Every film in a franchise, in the order they came out, numbered. The one you are looking at is
/// ringed; the others open their own page — owned or not, it is the same page.
///
/// Release order on purpose: a prequel that arrived fifth is shown fifth, because that is the order
/// a person watches a series in.
struct FranchiseRail: View {
    let franchise: Franchise
    let currentTmdbID: Int?

    var body: some View {
        PlexRail(title: franchise.name, id: "detail-franchise") {
            ForEach(Array(franchise.parts.enumerated()), id: \.element.id) { index, part in
                FranchisePoster(part: part, number: index + 1,
                                isCurrent: part.id == currentTmdbID)
            }
        }
    }
}

/// One film in the rail: its poster, its number in the series, and whether it is the one on screen.
private struct FranchisePoster: View {
    let part: TMDBSearchResult
    let number: Int
    let isCurrent: Bool

    @Environment(AppSession.self) private var session
    private let width = PosterTileMetrics.width
    private let height = PosterTileMetrics.height
    @FocusState private var focused: Bool

    var body: some View {
        let hit = SearchHit(result: part, kind: .movie)
        let owned = session.libraryStore?.ownedItem(tmdbID: part.id, kind: .movie)
        VStack(alignment: .leading, spacing: 22) {
            NavigationLink(value: BrowseDestination.detail(owned ?? .placeholder(for: hit))) {
                poster(owned: owned != nil)
            }
            .buttonStyle(FocusCardStyle())
            .focused($focused)
            Text("\(number). \(part.displayTitle)")
                .cardTitle()
                .lineLimit(1)
                .foregroundStyle(focused || isCurrent
                                 ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                .frame(width: width, alignment: .leading)
        }
    }

    @ViewBuilder private func poster(owned: Bool) -> some View {
        Group {
            if let url = TMDBClient.imageURL(path: part.posterPath, size: "w500") {
                RemoteImage(url: url)
            } else {
                Theme.Palette.surface1.overlay {
                    Text(part.displayTitle).cardTitle()
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.center).padding(10)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous))
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous)
                    .strokeBorder(Theme.Palette.strokeStrong, lineWidth: 4)
            }
        }
        .overlay(alignment: .topLeading) {
            Text("\(number)")
                .font(.seret(20, .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Theme.Palette.badgeBacking, in: Capsule())
                .padding(8)
        }
        .overlay(alignment: .topTrailing) {
            if owned {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.Palette.onFocus, Theme.Palette.textSecondary)
                    .padding(8)
                    .accessibilityLabel("In Library")
            }
        }
    }
}
