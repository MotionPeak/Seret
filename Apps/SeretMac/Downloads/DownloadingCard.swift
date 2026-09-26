import DebridCore
import DebridUI
import SwiftUI

/// A poster-sized card for an in-flight download: the art, a bottom strip with a download glyph +
/// the shared progress text over a gold bar, and the title below. Home's rail and My Library's
/// Downloading strip both use this. Disabled (no click, no menu) when the download has no page yet.
struct DownloadingCard: View {
    let tile: DownloadTile
    let library: LibraryStore?
    let onOpen: (MediaItem) -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var page: MediaItem? { tile.titleItem(in: library) }
    private var active: Bool { hovering && page != nil }

    var body: some View {
        Button {
            if let page { onOpen(page) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                art
                Text(tile.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: PosterCard.posterSize.width, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(page == nil)
        .onHover { hovering = $0 }
        .contextMenu {
            if let page {
                Button("Open") { onOpen(page) }
            }
        }
    }

    private var art: some View {
        RemoteImage(url: TMDBClient.imageURL(path: tile.posterPath, size: "w342"))
            .frame(width: PosterCard.posterSize.width, height: PosterCard.posterSize.height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay { rim }
            .overlay(alignment: .bottom) { statusStrip }
            .scaleEffect(active && !reduceMotion ? 1.03 : 1)
            .offset(y: active && !reduceMotion ? -6 : 0)
            .animation(Theme.Motion.quick, value: active)
    }

    @ViewBuilder private var rim: some View {
        if active {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.gold.opacity(0.75), lineWidth: 1.5)
                .goldGlow(16, opacity: 0.26)
        }
    }

    private var statusStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Palette.gold)
                Text(DownloadProgressText.line(for: tile.status))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            GoldProgressBar(fraction: tile.status.fraction)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background {
            Color.black.opacity(0.6)
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}
