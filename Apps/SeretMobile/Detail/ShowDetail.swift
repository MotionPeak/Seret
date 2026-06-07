import DebridCore
import DebridUI
import SwiftUI

/// Show Detail: backdrop, title + meta, overview, Play-next, a season picker, and the
/// episode list for the selected season.
struct ShowDetail: View {
    let store: DetailStore
    let onPlay: (PlaybackRequest) -> Void
    private var item: MediaItem { store.item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                Text(item.title).font(Theme.Typo.titleXL()).foregroundStyle(Theme.Palette.textPrimary)
                Text(metaLine).font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                if let overview = store.overview {
                    Text(overview).font(Theme.Typo.body())
                        .foregroundStyle(Theme.Palette.textSecondary).lineLimit(4)
                }
                heroAction
                seasonPicker
                episodeList
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.lg)
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
        HStack(spacing: Theme.Space.md) {
            if let next = store.nextEpisode() {
                Button {
                    onPlay(store.playRequest(source: next.source, episode: next,
                                             label: "\(item.title) — S\(next.season)·E\(next.number)"))
                } label: {
                    Label("Play S\(next.season)·E\(next.number)", systemImage: "play.fill")
                }
                .buttonStyle(GoldButtonStyle())
            }
            TrailerButton(tmdbID: item.tmdbID, kind: .show)
        }
    }

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                ForEach(item.seasons) { season in
                    let selected = season.number == store.selectedSeason
                    Button("Season \(season.number)") { Task { await store.selectSeason(season.number) } }
                        .font(Theme.Typo.headline())
                        .foregroundStyle(selected ? Color(hex: 0x1A1400) : Theme.Palette.textSecondary)
                        .padding(.vertical, 7).padding(.horizontal, Theme.Space.lg)
                        .background(selected ? AnyShapeStyle(Theme.Palette.goldGradient)
                                             : AnyShapeStyle(Theme.Palette.surface2), in: Capsule())
                }
            }
        }
    }

    @ViewBuilder private var episodeList: some View {
        if let season = item.seasons.first(where: { $0.number == store.selectedSeason }) {
            VStack(spacing: 0) {
                ForEach(season.episodes) { ep in
                    EpisodeRowView(store: store, episode: ep,
                                   meta: store.episodeMeta[season.number]?[ep.number], onPlay: onPlay)
                    Divider().overlay(Theme.Palette.hairline)
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
    let onPlay: (PlaybackRequest) -> Void

    private var contentKey: String { WatchKey.content(forShow: store.item, episode: episode) }
    private var watch: WatchState? { store.watchState(forKey: contentKey) }

    var body: some View {
        Button {
            onPlay(store.playRequest(source: episode.source, episode: episode, label: label))
        } label: {
            HStack(alignment: .top, spacing: Theme.Space.md) {
                still
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("\(episode.number). \(meta?.name ?? "Episode \(episode.number)")")
                            .font(Theme.Typo.headline()).foregroundStyle(Theme.Palette.textPrimary).lineLimit(1)
                        if watch?.finished == true {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.Palette.gold).font(.caption)
                        }
                    }
                    if let o = meta?.overview, !o.isEmpty {
                        Text(o).font(Theme.Typo.caption())
                            .foregroundStyle(Theme.Palette.textSecondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "play.circle.fill").foregroundStyle(Theme.Palette.gold)
            }
            .padding(.vertical, Theme.Space.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var still: some View {
        AsyncImage(url: TMDBClient.imageURL(path: meta?.stillPath, size: "w300")) { phase in
            if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
            else { ZStack { Theme.Palette.surface2; Image(systemName: "film").foregroundStyle(Theme.Palette.textTertiary) } }
        }
        .frame(width: 124, height: 70)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip))
    }

    private var label: String {
        "\(store.item.title) — S\(episode.season)·E\(episode.number)"
    }
}
