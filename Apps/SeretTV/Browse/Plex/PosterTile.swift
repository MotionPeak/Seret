import DebridCore
import SwiftUI

/// The rail tile: a bare 2:3 poster, no caption — Plex's idiom, where the preview header above
/// the rails says what the focused tile is.
///
/// Optional extras sit ON the art: a white progress line inset 12pt from the bottom, a chip at
/// the top centre ("Next", "New Season"…), and a white ✓ at the top right for a finished title.
/// With no poster the title is printed on a `surface1` card instead, so a title TMDB could not
/// match still says what it is.
///
/// Two flavours, one look: `init(…, value:)` is a `NavigationLink(value:)`; `init(…, action:)`
/// (where `Destination == Never`) is a plain button. Which one a tile is never changes after it
/// is built, so a background data change can never swap a focused tile's identity (CLAUDE.md,
/// focus traps).
struct PosterTile<Destination: Hashable>: View {
    let posterPath: String?
    let title: String
    var progress: Double?
    var chip: String?
    var watched: Bool
    let onFocus: () -> Void
    private let target: Target

    private enum Target {
        case link(Destination)
        case action(() -> Void)
    }

    init(posterPath: String?, title: String, progress: Double? = nil, chip: String? = nil,
         watched: Bool = false, onFocus: @escaping () -> Void = {}, value: Destination) {
        self.posterPath = posterPath; self.title = title; self.progress = progress
        self.chip = chip; self.watched = watched; self.onFocus = onFocus
        self.target = .link(value)
    }

    var body: some View {
        Group {
            switch target {
            case .link(let value): NavigationLink(value: value) { PosterTileArt(tile: artModel) }
            case .action(let action): Button(action: action) { PosterTileArt(tile: artModel) }
            }
        }
        .buttonStyle(FocusCardStyle())
        .reportsPlexRailFocus(onFocus)
        .accessibilityLabel(title)
    }

    private var artModel: PosterTileArt.Model {
        .init(posterPath: posterPath, title: title, progress: progress, chip: chip, watched: watched)
    }
}

extension PosterTile where Destination == Never {
    init(posterPath: String?, title: String, progress: Double? = nil, chip: String? = nil,
         watched: Bool = false, onFocus: @escaping () -> Void = {}, action: @escaping () -> Void) {
        self.posterPath = posterPath; self.title = title; self.progress = progress
        self.chip = chip; self.watched = watched; self.onFocus = onFocus
        self.target = .action(action)
    }
}

/// Rail tile metrics, from the approved mockup.
enum PosterTileMetrics {
    static let width: CGFloat = 236
    static let height: CGFloat = 354
}

/// What a `PosterTile` draws inside its focus ring.
private struct PosterTileArt: View {
    struct Model {
        let posterPath: String?
        let title: String
        let progress: Double?
        let chip: String?
        let watched: Bool
    }
    let tile: Model

    var body: some View {
        ZStack {
            if let url = TMDBClient.imageURL(path: tile.posterPath, size: "w500") {
                RemoteImage(url: url)
            } else {
                noArt
            }
        }
        .frame(width: PosterTileMetrics.width, height: PosterTileMetrics.height)
        .overlay { if tile.watched { Theme.Palette.artDim } }
        .overlay(alignment: .bottom) {
            if let progress = tile.progress, progress > 0 {
                ProgressLine(fraction: progress, height: 6)
                    .padding([.horizontal, .bottom], 12)
            }
        }
        .overlay(alignment: .top) {
            if let chip = tile.chip {
                Text(chip)
                    .font(.seret(19, .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Theme.Palette.surface1.opacity(0.88),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.top, 12)
            }
        }
        .overlay(alignment: .topTrailing) {
            if tile.watched {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.Palette.focus)
                    .background(Circle().fill(Theme.Palette.badgeBacking))
                    .padding(12)
                    .accessibilityLabel("Watched")
            }
        }
    }

    /// No artwork: the title on a palette surface, never a blank or grey block. Centred, and left
    /// to the text's own direction, so a Hebrew title reads right-to-left.
    private var noArt: some View {
        Theme.Palette.surface1
            .overlay {
                Text(tile.title)
                    .cardTitle()
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .minimumScaleFactor(0.8)
                    .padding(18)
            }
    }
}
