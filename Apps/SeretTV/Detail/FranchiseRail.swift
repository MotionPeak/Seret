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
        VStack(alignment: .leading, spacing: 12) {
            Text(franchise.name).sectionTitle()
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 30) {
                    ForEach(Array(franchise.parts.enumerated()), id: \.element.id) { index, part in
                        FranchisePoster(part: part, number: index + 1,
                                        isCurrent: part.id == currentTmdbID)
                    }
                }
                .padding(.vertical, 16)      // room for the focus lift
                .padding(.horizontal, 60)    // align + room for the focus scale at the edges
            }
            .padding(.horizontal, -60)       // edge-to-edge so a focused poster isn't clipped
        }
        // Widen the focus target to the page BEFORE sectioning — a section only counts when its
        // frame intersects the direction of travel.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }
}

/// One film in the rail: its poster, its number in the series, and whether it is the one on screen.
private struct FranchisePoster: View {
    let part: TMDBSearchResult
    let number: Int
    let isCurrent: Bool

    @Environment(AppSession.self) private var session
    private let width: CGFloat = 180
    private let height: CGFloat = 270
    @FocusState private var focused: Bool

    var body: some View {
        let hit = SearchHit(result: part, kind: .movie)
        let owned = session.libraryStore?.ownedItem(tmdbID: part.id)
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: BrowseDestination.detail(owned ?? .placeholder(for: hit))) {
                poster(owned: owned != nil)
            }
            .buttonStyle(.card)
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
                    .strokeBorder(Theme.Palette.gold, lineWidth: 4)
            }
        }
        .overlay(alignment: .topLeading) {
            Text("\(number)")
                .font(.seret(20, .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.black.opacity(0.65), in: Capsule())
                .padding(8)
        }
        .overlay(alignment: .topTrailing) {
            if owned {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.black, .yellow)
                    .padding(8)
                    .accessibilityLabel("In Library")
            }
        }
    }
}
