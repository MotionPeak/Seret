import DebridCore
import DebridUI
import SwiftUI

/// The art of a download in flight: the poster at rail size, with the live percent / remaining
/// time and a white progress line on a soft scrim along its bottom. Everything here sits INSIDE the
/// focus ring — it is the label of `DownloadingRailCard`'s button — so the card measures exactly
/// like a `PosterTile` and a Downloading rail lines up with the rails around it.
struct DownloadingTile: View {
    let tile: DownloadTile

    var body: some View {
        ZStack(alignment: .bottom) {
            poster
            LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text(DownloadProgressText.line(for: tile.status))
                }
                .font(.seret(19, .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                ProgressLine(fraction: tile.status.fraction, height: 6)
            }
            .padding([.horizontal, .bottom], 12)
        }
        .frame(width: PosterTileMetrics.width, height: PosterTileMetrics.height)
    }

    @ViewBuilder private var poster: some View {
        if let url = TMDBClient.imageURL(path: tile.posterPath, size: "w500") {
            RemoteImage(url: url)
        } else {
            // No artwork: the title on a palette surface, never a blank block.
            Theme.Palette.surface1
                .overlay(alignment: .top) {
                    Text(tile.title)
                        .cardTitle()
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(18)
                        .padding(.top, 40)
                }
        }
    }
}

/// The focusable form, for a Home rail or the My Library strip.
///
/// ⚠️ ONE NavigationLink whose *value* varies — never an owned/not-owned branch of two links.
/// A background library load flips ownership while the user browses; a branch swap destroys the
/// focused tile and tvOS drops focus somewhere unrelated (same defect as `BrowseTile`).
///
/// The ring goes round the art only: the optional caption sits below the button, outside it, so a
/// focused card never draws its ring round a line of text.
struct DownloadingRailCard: View {
    let tile: DownloadTile
    let destination: BrowseDestination
    /// The title under the card. Off in a Plex rail, where the preview header names the focused tile.
    var showsCaption = true
    /// Called when the card takes focus — a Plex rail drives its preview header with it.
    var onFocus: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: destination) {
                DownloadingTile(tile: tile)
            }
            .buttonStyle(FocusCardStyle())
            // Tells a `FocusBrowsePage` row that focus entered it; a no-op anywhere else.
            .reportsPlexRailFocus(onFocus)
            .accessibilityLabel(tile.title)
            if showsCaption {
                Text(tile.title)
                    .cardTitle()
                    .lineLimit(1)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: PosterTileMetrics.width, alignment: .leading)
            }
        }
    }
}

/// Where a download tile leads: the title's page — the owned item once it has landed, otherwise a
/// placeholder, which shows the same page with its download progress on it.
///
/// The shared `titleItem(in:)` decides, so the film-or-show choice is the tile's own (a film and a
/// show can share a TMDB id) and an unidentified tile (id 0) never matches an owned title.
@MainActor
func downloadDestination(for tile: DownloadTile, library: LibraryStore?) -> BrowseDestination {
    if let item = tile.titleItem(in: library) { return .detail(item) }
    let isShow = tile.status.contentKey.hasPrefix("show:")
    return .detail(.placeholder(for: SearchHit(result: TMDBSearchResult(
        id: tile.tmdbID, title: isShow ? nil : tile.title, name: isShow ? tile.title : nil,
        releaseDate: nil, firstAirDate: nil, posterPath: tile.posterPath,
        overview: nil, voteAverage: nil), kind: isShow ? .show : .movie)))
}
