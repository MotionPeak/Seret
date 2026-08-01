import DebridCore
import DebridUI
import SwiftUI

/// A poster tile for a download in flight, with live percent and remaining time.
/// Shared by the Home "Downloading" rail and the My Library strip so the two cannot drift apart.
struct DownloadingTile: View {
    let tile: DownloadTile
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                poster
                progressOverlay
            }
            .frame(width: 100, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip))
            Text(tile.title).font(Theme.Typo.caption()).lineLimit(1)
                .frame(width: 100, alignment: .leading).foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    @ViewBuilder private var poster: some View {
        if let url = TMDBClient.imageURL(path: tile.posterPath, size: "w300") {
            RemoteImage(url: url) { Rectangle().fill(.gray.opacity(0.25)) }
        } else {
            Rectangle().fill(.gray.opacity(0.25))
        }
    }

    private var progressOverlay: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                Text(DownloadProgressText.line(for: tile.status))
                Spacer()
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(.white)
            ProgressView(value: tile.status.fraction).tint(Theme.Palette.gold)
        }
        .padding(6)
        .background(.black.opacity(0.55))
    }
}

/// Where a download tile leads: the library Detail once the title is owned, otherwise the Add
/// screen, which is where an unfinished title's versions and progress live.
@MainActor
func openDownload(_ tile: DownloadTile, library: LibraryStore?, router: AppRouter) {
    if let owned = (library?.movies ?? []).first(where: { $0.tmdbID == tile.tmdbID })
        ?? (library?.shows ?? []).first(where: { $0.tmdbID == tile.tmdbID }) {
        router.detail = owned
        return
    }
    let isShow = tile.status.contentKey.hasPrefix("show:")
    router.addHit = SearchHit(result: TMDBSearchResult(
        id: tile.tmdbID, title: isShow ? nil : tile.title, name: isShow ? tile.title : nil,
        releaseDate: nil, firstAirDate: nil, posterPath: tile.posterPath,
        overview: nil, voteAverage: nil), kind: isShow ? .show : .movie)
}
