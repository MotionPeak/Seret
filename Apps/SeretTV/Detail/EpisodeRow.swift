import DebridCore
import SwiftUI

/// One episode in the vertical list: still + number/title + synopsis + progress, selectable
/// to play, with a context-menu Mark Watched/Unwatched.
struct EpisodeRow: View {
    let store: DetailStore
    let episode: Episode
    let meta: TMDBEpisodeDetails?

    private var contentKey: String { WatchKey.content(forShow: store.item, episode: episode) }
    private var watch: WatchState? { store.watchState(forKey: contentKey) }
    private var isWatched: Bool { watch?.finished == true }

    var body: some View {
        NavigationLink(value: store.playRequest(source: episode.source, episode: episode, label: label)) {
            HStack(alignment: .top, spacing: 20) {
                still
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(title).font(.title3.weight(.semibold))
                        if isWatched { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    if let overview = meta?.overview, !overview.isEmpty {
                        Text(overview).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                    progressBar
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .contextMenu {
            Button(isWatched ? "Mark Unwatched" : "Mark Watched") {
                Task { await store.setWatched(!isWatched, contentKey: contentKey, source: episode.source) }
            }
        }
        .frame(maxWidth: 1200, alignment: .leading)
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
                    placeholder: { Color.gray.opacity(0.3) }
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .frame(width: 214, height: 120).clipped().cornerRadius(8)
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
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(color).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(width: 214, height: 4)
    }
}
