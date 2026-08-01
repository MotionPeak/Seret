import DebridCore
import DebridUI
import SwiftUI

/// A poster tile for a download in flight, with live percent and remaining time.
/// Shared by the Home "Downloading" rail and the My Library strip so the two cannot drift apart.
struct DownloadingTile: View {
    let tile: DownloadTile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                poster
                progressOverlay
            }
            .frame(width: 180, height: 270)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous))
            Text(tile.title).font(.seretCallout).lineLimit(1)
                .frame(width: 180, alignment: .leading).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var poster: some View {
        if let url = TMDBClient.imageURL(path: tile.posterPath, size: "w500") {
            RemoteImage(url: url)
        } else {
            Theme.Palette.surface2
        }
    }

    private var progressOverlay: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                Text(DownloadProgressText.line(for: tile.status))
                Spacer()
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.white)
            .lineLimit(1)
            ProgressView(value: tile.status.fraction)
        }
        .padding(8).background(.black.opacity(0.6))
    }
}

/// The Home-rail form: the same tile, focusable and navigable.
///
/// ⚠️ ONE NavigationLink whose *value* varies — never an owned/not-owned branch of two links.
/// A background library load flips ownership while the user browses; a branch swap destroys the
/// focused tile and tvOS drops focus somewhere unrelated (same defect as `BrowseTile`).
struct DownloadingRailCard: View {
    let tile: DownloadTile
    let destination: BrowseDestination

    var body: some View {
        NavigationLink(value: destination) {
            DownloadingTile(tile: tile)
        }
        .buttonStyle(.card)
    }
}

/// Where a download tile leads: the library Detail once the title is owned, otherwise the Add
/// screen, which is where an unfinished title's versions and progress live.
@MainActor
func downloadDestination(for tile: DownloadTile, library: LibraryStore?) -> BrowseDestination {
    if let owned = (library?.movies ?? []).first(where: { $0.tmdbID == tile.tmdbID })
        ?? (library?.shows ?? []).first(where: { $0.tmdbID == tile.tmdbID }) {
        return .detail(owned)
    }
    let isShow = tile.status.contentKey.hasPrefix("show:")
    return .add(SearchHit(result: TMDBSearchResult(
        id: tile.tmdbID, title: isShow ? nil : tile.title, name: isShow ? tile.title : nil,
        releaseDate: nil, firstAirDate: nil, posterPath: tile.posterPath,
        overview: nil, voteAverage: nil), kind: isShow ? .show : .movie))
}
