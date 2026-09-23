import DebridCore
import DebridUI
import SwiftUI

/// The selected season's episodes: TMDB's list merged with whatever is downloaded
/// (`store.episodes(forSeason:)`), reflowing 1/2/3-up with the container's own measured width —
/// not the window's — since it sits inside the page's padded body.
struct EpisodeGrid: View {
    let store: DetailStore

    @Environment(ShellModel.self) private var shell: ShellModel?
    @State private var width: CGFloat = 900

    private var rows: [DetailStore.EpisodeRowInfo] { store.episodes(forSeason: store.selectedSeason) }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 22), count: TitlePageLayout.episodeColumns(width: width))
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
            ForEach(rows) { row in
                EpisodeCard(store: store, row: row) { request in shell?.present(request) }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

private struct EpisodeCard: View {
    let store: DetailStore
    let row: DetailStore.EpisodeRowInfo
    let onPlay: (PlaybackRequest) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var key: String { WatchKey.content(forShow: store.item, season: row.season, number: row.number) }
    private var watchState: WatchState? { store.watchState(forKey: key) }
    private var badge: WatchBadge { WatchBadge(watchState) }
    private var active: Bool { row.isDownloaded && hovering }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            still
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(row.number)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Palette.gold)
                Text(row.meta?.name ?? "Episode \(row.number)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
            }
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(row.isDownloaded ? Theme.Palette.textSecondary : Theme.Palette.textTertiary)
            }
        }
        .opacity(row.isDownloaded ? 1 : 0.45)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if row.isDownloaded { play(fromStart: false) } }
        .contextMenu { contextMenuItems }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var still: some View {
        RemoteImage(url: TMDBClient.imageURL(path: row.meta?.stillPath ?? store.backdropPath, size: "w500"))
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(alignment: .topTrailing) { watchedMark }
            .overlay(alignment: .bottom) { progressLine }
            .overlay { playGlyph }
            .overlay { rim }
            .offset(y: active && !reduceMotion ? -4 : 0)
            .animation(Theme.Motion.quick, value: active)
    }

    @ViewBuilder private var watchedMark: some View {
        if badge == .watched {
            ZStack {
                Circle().fill(Color.black.opacity(0.6))
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.Palette.gold)
            }
            .frame(width: 22, height: 22)
            .padding(8)
        }
    }

    @ViewBuilder private var progressLine: some View {
        if case let .progress(fraction) = badge {
            GoldProgressBar(fraction: fraction)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
    }

    @ViewBuilder private var playGlyph: some View {
        if active {
            ZStack {
                Circle().fill(Color.black.opacity(0.55))
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
        }
    }

    @ViewBuilder private var rim: some View {
        if active {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.gold.opacity(0.75), lineWidth: 1.5)
                .goldGlow(14, opacity: 0.25)
        }
    }

    private var caption: String {
        guard row.isDownloaded else { return "Not downloaded" }
        guard let runtime = row.meta?.runtime else { return "" }
        return "\(runtime)m"
    }

    private func play(fromStart: Bool) {
        guard let request = store.episodePlayRequest(for: row, fromStart: fromStart) else { return }
        onPlay(request)
    }

    @ViewBuilder private var contextMenuItems: some View {
        if row.isDownloaded {
            Button("Play") { play(fromStart: false) }
            if let watchState, !watchState.finished, watchState.positionSeconds > 0 {
                Button("Play from Beginning") { play(fromStart: true) }
            }
            Divider()
        }
        let watched = watchState?.finished ?? false
        Button(watched ? "Mark as Unwatched" : "Mark as Watched") {
            Task { await store.setWatched(!watched, contentKey: key, source: row.ownedSource) }
        }
    }

    private var accessibilityLabel: String {
        let name = row.meta?.name ?? "Episode \(row.number)"
        guard row.isDownloaded else { return "Episode \(row.number), \(name), not downloaded" }
        switch badge {
        case .watched: return "Episode \(row.number), \(name), watched"
        case .progress(let fraction): return "Episode \(row.number), \(name), \(Int((fraction * 100).rounded())) percent watched"
        case .none: return "Episode \(row.number), \(name)"
        }
    }
}
