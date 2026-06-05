import DebridCore
import DebridUI
import SwiftUI

/// Show Detail: backdrop, title + meta, overview, Play-next, a season picker, and the
/// episode list for the selected season.
struct ShowDetail: View {
    let store: DetailStore
    private var item: MediaItem { store.item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(item.title).font(.largeTitle.bold())
                Text(metaLine).font(.subheadline).foregroundStyle(.secondary)
                if let overview = store.overview {
                    Text(overview).font(.callout).foregroundStyle(.secondary).lineLimit(4)
                }
                heroAction
                seasonPicker
                episodeList
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .padding(.top, 200)
        }
        .background(DetailBackdrop(path: store.backdropPath, posterFallback: item.posterPath))
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var metaLine: String {
        var parts: [String] = []
        if let y = item.year { parts.append(String(y)) }
        if !store.genres.isEmpty { parts.append(store.genres.prefix(3).joined(separator: " · ")) }
        parts.append("\(item.seasons.count) Season\(item.seasons.count == 1 ? "" : "s")")
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder private var heroAction: some View {
        if let next = store.nextEpisode() {
            NavigationLink(value: store.playRequest(
                source: next.source, episode: next,
                label: "\(item.title) — S\(next.season)·E\(next.number)")) {
                Label("Play S\(next.season)·E\(next.number)", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(item.seasons) { season in
                    Button("Season \(season.number)") {
                        Task { await store.selectSeason(season.number) }
                    }
                    .buttonStyle(.bordered)
                    .tint(season.number == store.selectedSeason ? .primary : .secondary)
                }
            }
        }
    }

    @ViewBuilder private var episodeList: some View {
        if let season = item.seasons.first(where: { $0.number == store.selectedSeason }) {
            VStack(spacing: 0) {
                ForEach(season.episodes) { ep in
                    EpisodeRowView(store: store, episode: ep,
                                   meta: store.episodeMeta[season.number]?[ep.number])
                    Divider()
                }
            }
        }
    }
}

/// One episode row: number + title (from TMDB when loaded), synopsis, watched check, tap → Play.
struct EpisodeRowView: View {
    let store: DetailStore
    let episode: Episode
    let meta: TMDBEpisodeDetails?

    private var contentKey: String { WatchKey.content(forShow: store.item, episode: episode) }
    private var watch: WatchState? { store.watchState(forKey: contentKey) }

    var body: some View {
        NavigationLink(value: store.playRequest(source: episode.source, episode: episode, label: label)) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("\(episode.number). \(meta?.name ?? "Episode \(episode.number)")")
                            .font(.callout.weight(.medium))
                        if watch?.finished == true {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                        }
                    }
                    if let o = meta?.overview, !o.isEmpty {
                        Text(o).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "play.circle").foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var label: String {
        "\(store.item.title) — S\(episode.season)·E\(episode.number)"
    }
}
