import DebridCore
import DebridUI
import SwiftUI

/// One episode card in the side-scrolling row: a 16:9 still (the focusable `.card`). A downloaded
/// episode plays on select (with a Mark Watched context menu); a not-downloaded one shows a
/// download glyph + "Not downloaded" and downloads-then-plays on select.
struct EpisodeRow: View {
    let store: DetailStore
    let row: DetailStore.EpisodeRowInfo
    var isDownloading: Bool = false
    var onDownload: (DetailStore.EpisodeRowInfo) -> Void = { _ in }

    private let width: CGFloat = 320

    private var contentKey: String? { row.ownedEpisode.map { WatchKey.content(forShow: store.item, episode: $0) } }
    private var watch: WatchState? { contentKey.flatMap { store.watchState(forKey: $0) } }
    private var isWatched: Bool { watch?.finished == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let ep = row.ownedEpisode, let src = row.ownedSource {
                NavigationLink(value: store.playRequest(source: src, episode: ep, label: label)) {
                    still
                }
                .buttonStyle(.card)
                .contextMenu {
                    Button(isWatched ? "Mark Unwatched" : "Mark Watched") {
                        Task { await store.setWatched(!isWatched, contentKey: contentKey ?? "", source: src) }
                    }
                }
            } else {
                Button { onDownload(row) } label: { still }
                    .buttonStyle(.card)
                    .disabled(isDownloading)
            }
            HStack(spacing: 8) {
                Text(title).font(.headline).lineLimit(1)
                if isWatched { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private var label: String { "\(store.item.title) — S\(row.season)·E\(row.number)" }
    private var title: String { "\(row.number) · \(row.meta?.name ?? "Episode \(row.number)")" }
    private var subtitle: String {
        if isDownloading { return "Downloading\u{2026}" }
        if !row.isDownloaded { return "Not downloaded" }
        return [row.meta?.runtime.map { "\($0) min" }, row.ownedSource?.parsed.resolution]
            .compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private var still: some View {
        Group {
            if let url = TMDBClient.imageURL(path: row.meta?.stillPath, size: "w300") {
                AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { ZStack { Color.gray.opacity(0.25); ProgressView() } }
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .frame(width: width, height: width * 9 / 16)
        .clipped()
        .opacity(row.isDownloaded ? 1 : 0.5)          // dim not-downloaded episodes
        .overlay {
            if !row.isDownloaded {
                Image(systemName: isDownloading ? "arrow.down.circle" : "arrow.down.circle.fill")
                    .font(.system(size: 44)).foregroundStyle(.white.opacity(0.9))
                    .symbolEffect(.pulse, isActive: isDownloading)
            }
        }
        .overlay(alignment: .bottom) { progressBar }
    }

    @ViewBuilder private var progressBar: some View {
        if isWatched {
            bar(fraction: 1, color: .green)
        } else if let w = watch, w.durationSeconds > 0, w.positionSeconds > 0 {
            bar(fraction: w.positionSeconds / w.durationSeconds, color: .white)
        }
    }

    private func bar(fraction: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.black.opacity(0.4)
                Capsule().fill(color).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 5)
    }
}
