import DebridCore
import DebridUI
import SwiftUI

/// One focusable poster tile. The poster itself is the `.card` (tvOS focus lift + ring); the title
/// sits *below* the card as plain text — no grey caption box — so the grid reads cleanly.
struct PosterCard: View {
    let item: MediaItem
    /// A finished MOVIE — dims the poster + shows a ✓ badge, and flips the menu's toggle label.
    var watched: Bool = false
    var onRemove: (MediaItem) -> Void = { _ in }
    /// Press-and-hold → mark a movie watched/unwatched (movies only; shows are marked per-episode).
    var onToggleWatched: (MediaItem) -> Void = { _ in }

    private let width: CGFloat = 220
    private let height: CGFloat = 330
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: item) { poster }
                .buttonStyle(.card)
                .focused($focused)
                .contextMenu {
                    if item.kind == .movie {
                        Button(watched ? "Mark Unwatched" : "Mark Watched",
                               systemImage: watched ? "checkmark.circle.fill" : "checkmark.circle") {
                            onToggleWatched(item)
                        }
                    }
                    Button("Remove from Library", systemImage: "trash", role: .destructive) {
                        onRemove(item)
                    }
                }
            // The title ties to its poster: it brightens when the card is focused, so the focused
            // cell reads as one unit instead of a lone lifted poster over grey text.
            Text(item.title)
                .cardTitle()
                .lineLimit(1)
                .foregroundStyle(focused ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                .frame(width: width, alignment: .leading)
                .animation(Theme.Anim.focus, value: focused)
        }
    }

    @ViewBuilder private var poster: some View {
        Group {
            if let url = TMDBClient.imageURL(path: item.posterPath, size: "w500") {
                RemoteImage(url: url)
            } else {
                noPoster
            }
        }
        .frame(width: width, height: height)
        .overlay { if watched { Color.black.opacity(0.45) } }   // dim a watched movie
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if watched {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.Palette.gold)
                    .background(Circle().fill(.black.opacity(0.55)))
                    .padding(12)
                    .accessibilityLabel("Watched")
            }
        }
    }

    /// No artwork available — fall back to the title on a palette surface (not a raw grey block).
    private var noPoster: some View {
        Theme.Palette.surface1
            .overlay {
                Text(item.title)
                    .cardTitle()
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(12)
            }
    }
}
