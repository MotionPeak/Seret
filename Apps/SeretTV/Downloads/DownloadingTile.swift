import DebridCore
import DebridUI
import SwiftUI

/// The art of a download in flight: the poster at rail size, with the live percent / remaining
/// time and a white progress line on a soft scrim along its bottom. Everything here sits INSIDE the
/// focus ring — it is the label of `DownloadingRailCard`'s button — so the card measures exactly
/// like a `PosterTile` and a Downloading rail lines up with the rails around it.
struct DownloadingTile: View {
    let tile: DownloadTile
    /// The download is no longer in flight, but the card is still on screen (My Library holds its
    /// strip's shape while focus is in it). Drawn settled — dimmed, no progress line, and what
    /// became of it when that is known — never frozen at its last percent.
    var settled: DownloadSettled?

    var body: some View {
        ZStack(alignment: .bottom) {
            poster
            LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
            if settled != nil { Theme.Palette.artDim }
            VStack(alignment: .leading, spacing: 10) {
                if let settled {
                    if let label = settled.label {
                        Label(label.text, systemImage: label.symbol)
                            .font(.seret(19, .semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(1)
                    }
                } else {
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
    /// The card's `plexFocusID` on a `FocusBrowsePage` — its `initialFocus` hook and the id the
    /// page's focus handle reports. Applied to the button itself, not the card with its caption,
    /// so the id names the view that actually takes focus.
    var focusID: String?
    /// Called when the card takes focus — a Plex rail drives its preview header with it.
    var onFocus: () -> Void = {}
    /// See `DownloadingTile.settled`.
    var settled: DownloadSettled?

    var body: some View {
        // 22, not 12: a focused card grows ~14pt past its frame and the ring adds 4, so the caption
        // sits clear of the ring instead of under it.
        VStack(alignment: .leading, spacing: 22) {
            NavigationLink(value: destination) {
                DownloadingTile(tile: tile, settled: settled)
            }
            .buttonStyle(FocusCardStyle())
            // Tells a `FocusBrowsePage` row that focus entered it; a no-op anywhere else.
            .reportsPlexRailFocus(onFocus)
            .modifier(CardFocusID(id: focusID))
            .accessibilityLabel(tile.title)
            if showsCaption {
                Text(tile.title)
                    .cardTitle()
                    .lineLimit(1)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: PosterTileMetrics.width, alignment: .leading)
                    // The button already speaks the title.
                    .accessibilityHidden(true)
            }
        }
    }
}

/// `plexFocusID` when a page names the card; nothing otherwise. Which branch a card takes is fixed
/// when it is built, so it never swaps under focus.
private struct CardFocusID: ViewModifier {
    let id: String?

    func body(content: Content) -> some View {
        if let id { content.plexFocusID(id) } else { content }
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

/// What became of a download whose card is still on screen after it left the in-flight list.
enum DownloadSettled: Equatable {
    case ready, failed
    /// Gone from the list with nothing known — cancelled, or forgotten once the library carried it.
    case ended

    init(phase: DownloadStatus.Phase?) {
        switch phase {
        case .ready: self = .ready
        case .failed: self = .failed
        default: self = .ended
        }
    }

    var label: (text: String, symbol: String)? {
        switch self {
        case .ready: ("Ready", "checkmark.circle.fill")
        case .failed: ("Failed", "exclamationmark.triangle.fill")
        case .ended: nil
        }
    }
}
