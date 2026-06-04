import DebridCore
import SwiftUI

/// Show Detail: backdrop hero with Resume/Play-next, a focusable season picker, and the
/// vertical episode list for the selected season.
struct ShowDetailView: View {
    let store: DetailStore
    private var item: MediaItem { store.item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Bottom-anchored hero over the backdrop; the season picker + episodes follow below.
                hero.frame(maxWidth: .infinity, minHeight: 560, alignment: .bottomLeading)
                seasonPicker
                episodeList
            }
            .padding(60)
        }
        .background(BackdropBackground(path: store.backdropPath, posterFallback: item.posterPath))
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(item.title).font(.system(size: 60, weight: .bold))
            Text(metaLine).font(.title3).foregroundStyle(.secondary)
            if let overview = store.overview {
                Text(overview).font(.title3).frame(maxWidth: 1100, alignment: .leading).lineLimit(3)
            }
            heroActions
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let y = item.year { parts.append(String(y)) }
        if !store.genres.isEmpty { parts.append(store.genres.prefix(3).joined(separator: " · ")) }
        parts.append("\(item.seasons.count) Season\(item.seasons.count == 1 ? "" : "s")")
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder private var heroActions: some View {
        if let next = store.nextEpisode() {
            let resume = store.watchState(forKey: WatchKey.content(forShow: item, episode: next))
                .flatMap { (!$0.finished && $0.positionSeconds > 0) ? $0.positionSeconds : nil }
            NavigationLink(value: store.playRequest(
                source: next.source, episode: next,
                label: "\(item.title) — S\(next.season)·E\(next.number)")) {
                Label(resume != nil ? "Resume S\(next.season)·E\(next.number)"
                                    : "Play S\(next.season)·E\(next.number)",
                      systemImage: "play.fill")
            }
            .font(.title3)
        }
    }

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(item.seasons) { season in
                    Button { Task { await store.selectSeason(season.number) } } label: {
                        Text("Season \(season.number)").font(.title3.weight(.semibold))
                            .padding(.horizontal, 22).padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(season.number == store.selectedSeason ? .white : .gray)
                }
            }
        }
    }

    @ViewBuilder private var episodeList: some View {
        if let season = item.seasons.first(where: { $0.number == store.selectedSeason }) {
            VStack(spacing: 22) {
                ForEach(season.episodes) { ep in
                    EpisodeRow(store: store, episode: ep, meta: store.episodeMeta[season.number]?[ep.number])
                }
            }
        }
    }
}

#Preview {
    func ep(_ n: Int) -> Episode {
        Episode(season: 1, number: n,
                source: MediaSource(torrentID: "t\(n)", fileID: nil, restrictedLink: "l",
                                    parsed: ParsedRelease(title: "x", resolution: "1080p", source: "WEB-DL")))
    }
    let item = MediaItem(id: "9", kind: .show, title: "Game of Thrones", year: 2011, sources: [],
                         seasons: [Season(number: 1, episodes: [ep(1), ep(2), ep(3)])],
                         tmdbID: nil, overview: "Nine noble families fight for control…")
    return NavigationStack {
        ShowDetailView(store: DetailStore(item: item, details: PreviewDetailsShow(), watch: nil))
    }
}

private struct PreviewDetailsShow: MediaDetailsProviding {
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw CancellationError() }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw CancellationError() }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
}
