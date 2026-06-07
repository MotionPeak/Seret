import DebridCore
import DebridUI
import SwiftUI

/// Show Detail: backdrop hero with Resume/Play-next, a focusable season picker, and the
/// vertical episode list for the selected season.
struct ShowDetailView: View {
    let store: DetailStore
    var onRemove: () -> Void = {}
    /// Builds a whole-season download engine for (imdbID, season, originalLanguage); injected so the
    /// Preview (which has no AppSession) stays buildable. Returns nil when Stage 2 is unavailable.
    var makeSeasonDownload: (String, Int, String?) -> AddStore? = { _, _, _ in nil }
    var onSeasonAdded: () -> Void = {}
    /// A not-downloaded episode was selected → download-then-play (handled by DetailView).
    var onDownloadEpisode: (DetailStore.EpisodeRowInfo) -> Void = { _ in }
    var downloadingEpisodeID: String? = nil
    @State private var seasonStore: AddStore?
    private var item: MediaItem { store.item }

    /// Re-keys the season-pack lookup whenever the resolved imdbID or the selected season changes.
    private var seasonDownloadKey: String { "\(store.imdbID ?? "")#\(store.selectedSeason)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Bottom-anchored hero over the backdrop; the season picker + episodes follow below.
                hero.frame(maxWidth: .infinity, minHeight: 560, alignment: .bottomLeading)
                seasonPicker
                SeasonDownloadButton(store: seasonStore, onAdded: onSeasonAdded)
                episodeList
            }
            .padding(60)
        }
        .background(BackdropBackground(path: store.backdropPath, posterFallback: item.posterPath))
        .task(id: seasonDownloadKey) {
            guard let imdb = store.imdbID else { return }
            let s = makeSeasonDownload(imdb, store.selectedSeason, store.originalLanguage)
            seasonStore = s
            await s?.loadStreams()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(item.title).font(.system(size: 46, weight: .bold))
            Text(metaLine).font(.body).foregroundStyle(.secondary)
            if let overview = store.overview {
                Text(overview).font(.body).frame(maxWidth: 1100, alignment: .leading).lineLimit(3)
            }
            heroActions
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let y = item.year { parts.append(String(y)) }
        if !store.genres.isEmpty { parts.append(store.genres.prefix(3).joined(separator: " · ")) }
        let n = store.allSeasons.count
        parts.append("\(n) Season\(n == 1 ? "" : "s")")
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder private var heroActions: some View {
        HStack(spacing: 20) {
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
            }
            TrailerButton(tmdbID: item.tmdbID, kind: .show)
            Button(role: .destructive) { onRemove() } label: {
                Label("Remove from Library", systemImage: "trash")
            }
        }
        .font(.title3)
    }

    @ViewBuilder private var seasonPicker: some View {
        if store.allSeasons.count > 1 {   // a single-season show needs no picker (and avoids a lone chip)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(store.allSeasons, id: \.self) { number in
                        Button { Task { await store.selectSeason(number) } } label: {
                            Text("Season \(number)").font(.headline)
                                .padding(.horizontal, 18).padding(.vertical, 9)
                        }
                        // Gold tint for the selected season — never white, which would render the
                        // label white-on-white (a blank focused capsule) on tvOS.
                        .buttonStyle(.bordered)
                        .tint(number == store.selectedSeason ? Theme.Palette.gold : Theme.Palette.textSecondary)
                    }
                }
            }
        }
    }

    private var episodeList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 30) {
                ForEach(store.episodes(forSeason: store.selectedSeason)) { row in
                    EpisodeRow(store: store, row: row,
                               isDownloading: downloadingEpisodeID == row.id,
                               onDownload: onDownloadEpisode)
                }
            }
            .padding(.vertical, 16)   // room for the focus lift
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
