import DebridCore
import DebridUI
import SwiftUI

/// A poster tile for a download in flight: the poster dimmed at its foot, the live percent and
/// time left, and a white progress line — the same rounded 2:3 tile as every rail.
/// Shared by the Home "Downloading" rail and the My Library strip so the two cannot drift apart.
struct DownloadingTile: View {
    let tile: DownloadTile
    var width: CGFloat = 100
    /// The title under the poster (the My Library strip); Home's rail, like its others, has none.
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay { poster }
                .overlay(alignment: .bottom) { progressOverlay }
                .clipShape(RoundedRectangle(cornerRadius: PosterTileMetrics.corner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PosterTileMetrics.corner, style: .continuous)
                    .stroke(Theme.Palette.hairline, lineWidth: 0.5))
            if showsTitle {
                Text(tile.title).font(Theme.Typo.caption()).lineLimit(1)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .frame(width: width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.title), downloading, \(DownloadProgressText.line(for: tile.status))")
    }

    @ViewBuilder private var poster: some View {
        if let url = TMDBClient.imageURL(path: tile.posterPath, size: "w342") {
            RemoteImage(url: url) { noArt }
        } else {
            noArt
        }
    }

    private var noArt: some View {
        Theme.Palette.surface1.overlay {
            Text(tile.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center).lineLimit(4).padding(10)
        }
    }

    private var progressOverlay: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                Text(DownloadProgressText.line(for: tile.status))
            }
            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1).minimumScaleFactor(0.8)
            ProgressLine(fraction: tile.status.fraction, height: 3)
        }
        .padding(.horizontal, 8).padding(.bottom, 8).padding(.top, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.75)],
                                   startPoint: .top, endPoint: .bottom))
    }
}

/// Where a download tile leads: the title's page — the owned item once it has landed, otherwise a
/// placeholder, which shows the same page with its download progress on it.
@MainActor
func openDownload(_ tile: DownloadTile, library: LibraryStore?, router: AppRouter) {
    if let owned = (library?.movies ?? []).first(where: { $0.tmdbID == tile.tmdbID })
        ?? (library?.shows ?? []).first(where: { $0.tmdbID == tile.tmdbID }) {
        router.detail = owned
        return
    }
    let isShow = tile.status.contentKey.hasPrefix("show:")
    router.detail = .placeholder(for: SearchHit(result: TMDBSearchResult(
        id: tile.tmdbID, title: isShow ? nil : tile.title, name: isShow ? tile.title : nil,
        releaseDate: nil, firstAirDate: nil, posterPath: tile.posterPath,
        overview: nil, voteAverage: nil), kind: isShow ? .show : .movie))
}
