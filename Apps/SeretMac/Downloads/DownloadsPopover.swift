import DebridCore
import DebridUI
import SwiftUI

/// The sidebar downloads card's popover: one row per active download, each opening its page (once
/// it has one) and closing the popover.
struct DownloadsPopover: View {
    let tiles: [DownloadTile]
    let library: LibraryStore?
    let onOpen: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DOWNLOADING")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.Palette.gold)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(tiles) { tile in
                        row(for: tile)
                    }
                }
            }
            .frame(maxHeight: 350)
        }
        .padding(16)
        .frame(width: 340)
        .background(Theme.Palette.canvas)
    }

    private func row(for tile: DownloadTile) -> some View {
        let page = tile.titleItem(in: library)
        return Button {
            if let page { onOpen(page) }
        } label: {
            HStack(spacing: 10) {
                RemoteImage(url: TMDBClient.imageURL(path: tile.posterPath, size: "w185"))
                    .frame(width: 36, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(tile.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    GoldProgressBar(fraction: tile.status.fraction).frame(height: 3)
                    Text(DownloadProgressText.line(for: tile.status))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .disabled(page == nil)
    }
}
