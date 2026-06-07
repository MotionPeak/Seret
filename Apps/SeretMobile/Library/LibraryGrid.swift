import DebridCore
import DebridUI
import SwiftUI

/// Renders one library tab (Movies or Shows): an adaptive poster grid when loaded
/// (~3 columns on iPhone, larger posters/more columns on iPad), otherwise the
/// loading / empty / failed state — all on the Gold Glass canvas.
struct LibraryGrid: View {
    let title: String
    let items: [MediaItem]
    let state: LibraryStore.State
    let onRetry: () -> Void
    let onSelect: (MediaItem) -> Void
    let onRemove: (MediaItem) -> Void
    @Environment(\.horizontalSizeClass) private var hSize

    private var columns: [GridItem] {
        let minW: CGFloat = hSize == .regular ? 158 : 110
        let maxW: CGFloat = hSize == .regular ? 220 : 170
        return [GridItem(.adaptive(minimum: minW, maximum: maxW), spacing: Theme.Space.lg)]
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            loadingGrid
        case .failed(let msg):
            message("Couldn't load", systemImage: "exclamationmark.triangle", detail: msg, retry: true)
        case .empty:
            message("Nothing in your library yet", systemImage: "tray",
                    detail: "Add content to your Real‑Debrid account and it appears here.", retry: false)
        case .loaded:
            if items.isEmpty {
                message("No \(title.lowercased()) yet", systemImage: "tray", detail: nil, retry: false)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Theme.Space.xl) {
                        ForEach(items) { item in
                            Button { onSelect(item) } label: {
                                PosterCard(title: item.title,
                                           posterURL: TMDBClient.imageURL(path: item.posterPath, size: "w500"),
                                           width: nil)
                            }
                            .pressable()
                            .contextMenu {
                                Button("Remove from Library", systemImage: "trash", role: .destructive) {
                                    onRemove(item)
                                }
                            }
                        }
                    }
                    .padding(Theme.Space.lg)
                }
            }
        }
    }

    private var loadingGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Space.xl) {
                ForEach(0..<12, id: \.self) { _ in
                    Color.clear.aspectRatio(2.0 / 3.0, contentMode: .fit).overlay { ShimmerView() }
                }
            }
            .padding(Theme.Space.lg)
        }
    }

    private func message(_ title: String, systemImage: String, detail: String?, retry: Bool) -> some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: systemImage).font(.system(size: 42)).foregroundStyle(Theme.Palette.gold)
            Text(title).font(Theme.Typo.headline()).foregroundStyle(Theme.Palette.textPrimary)
            if let detail {
                Text(detail).font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if retry {
                Button("Try Again", action: onRetry).buttonStyle(GhostButtonStyle()).padding(.top, Theme.Space.sm)
            }
        }
        .padding(Theme.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
