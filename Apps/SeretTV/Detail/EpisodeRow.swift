import DebridCore
import DebridUI
import SwiftUI

/// One episode card in the side-scrolling row: a 16:9 still (the focusable `.card`) with the
/// number/title, runtime·resolution, and a progress bar below. Select to play; context-menu
/// Mark Watched/Unwatched.
struct EpisodeRow: View {
    let store: DetailStore
    let episode: Episode
    let meta: TMDBEpisodeDetails?

    private let width: CGFloat = 320

    private var contentKey: String { WatchKey.content(forShow: store.item, episode: episode) }
    private var watch: WatchState? { store.watchState(forKey: contentKey) }
    private var isWatched: Bool { watch?.finished == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: store.playRequest(source: episode.source, episode: episode, label: label)) {
                still
            }
            .buttonStyle(.card)
            .contextMenu {
                Button(isWatched ? "Mark Unwatched" : "Mark Watched") {
                    Task { await store.setWatched(!isWatched, contentKey: contentKey, source: episode.source) }
                }
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

    private var label: String { "\(store.item.title) — S\(episode.season)·E\(episode.number)" }
    private var title: String { "\(episode.number) · \(meta?.name ?? "Episode \(episode.number)")" }
    private var subtitle: String {
        [meta?.runtime.map { "\($0) min" }, episode.source.parsed.resolution]
            .compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private var still: some View {
        Group {
            if let url = TMDBClient.imageURL(path: meta?.stillPath, size: "w300") {
                AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { ZStack { Color.gray.opacity(0.25); ProgressView() } }
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .frame(width: width, height: width * 9 / 16)
        .clipped()
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
