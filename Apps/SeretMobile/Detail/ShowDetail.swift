import DebridCore
import DebridUI
import SwiftUI

/// Show Detail: backdrop, title + meta, overview, Play-next, an all-seasons picker, and the full
/// episode list for the selected season. Every TMDB episode is shown — downloaded ones play, the
/// rest say "Not downloaded" and download-then-play on tap.
struct ShowDetail: View {
    let store: DetailStore
    let onPlay: (PlaybackRequest) -> Void
    /// Builds a whole-season download engine for (imdbID, season, originalLanguage); injected so the
    /// view stays buildable without an AppSession. Returns nil when Stage 2 is unavailable.
    var makeSeasonDownload: (String, Int, String?) -> AddStore? = { _, _, _ in nil }
    /// Builds a single-episode download engine for (imdbID, season, episode, originalLanguage).
    var makeEpisodeDownload: (String, Int, Int, String?) -> AddStore? = { _, _, _, _ in nil }
    var onSeasonAdded: () -> Void = {}
    @State private var seasonStore: AddStore?
    @State private var downloadingEpisodeID: String?
    private var item: MediaItem { store.item }

    /// Re-keys the season-pack lookup whenever the resolved imdbID or selected season changes.
    private var seasonDownloadKey: String { "\(store.imdbID ?? "")#\(store.selectedSeason)" }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TrailerHero(tmdbID: item.tmdbID, kind: .show,
                            backdropPath: store.backdropPath, posterFallback: item.posterPath)
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                Text(item.title).font(Theme.Typo.titleXL()).foregroundStyle(Theme.Palette.textPrimary)
                Text(metaLine).font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                RatingsRow(ratings: store.ratings)
                if let overview = store.overview {
                    Text(overview).font(Theme.Typo.body())
                        .foregroundStyle(Theme.Palette.textSecondary).lineLimit(4)
                }
                heroAction
                seasonPicker
                SeasonDownloadButton(store: seasonStore, onAdded: onSeasonAdded)
                episodeList
            }
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)            // center the readable column (no left-edge cropping on iPad)
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.lg)
            .padding(.bottom, Theme.Space.xxl)
            }
        }
        .background(CanvasBackground())
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: seasonDownloadKey) {
            guard let imdb = store.imdbID else { return }
            let s = makeSeasonDownload(imdb, store.selectedSeason, store.originalLanguage)
            seasonStore = s
            await s?.loadStreams()
        }
        // Warm the season's episode stills as soon as its TMDB metadata lands (the id re-fires
        // when the meta count changes), so the list renders with images, not grey tiles.
        .task(id: "stills#\(store.selectedSeason)#\(store.episodeMeta[store.selectedSeason]?.count ?? 0)") {
            let stills = store.episodes(forSeason: store.selectedSeason)
                .compactMap { TMDBClient.imageURL(path: $0.meta?.stillPath, size: "w300") }
            ImageMemoryCache.prefetch(stills)
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
        }
    }

    @ViewBuilder private var seasonPicker: some View {
        if store.allSeasons.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(store.allSeasons, id: \.self) { n in
                        let selected = n == store.selectedSeason
                        Button("Season \(n)") { Task { await store.selectSeason(n) } }
                            .font(Theme.Typo.headline())
                            .foregroundStyle(selected ? Color(hex: 0x1A1400) : Theme.Palette.textSecondary)
                            .padding(.vertical, 7).padding(.horizontal, Theme.Space.lg)
                            .background(selected ? AnyShapeStyle(Theme.Palette.goldGradient)
                                                 : AnyShapeStyle(Theme.Palette.surface2), in: Capsule())
                    }
                }
            }
        }
    }

    private var episodeList: some View {
        VStack(spacing: 0) {
            ForEach(store.episodes(forSeason: store.selectedSeason)) { row in
                EpisodeRowView(store: store, row: row, isDownloading: downloadingEpisodeID == row.id,
                               onPlay: onPlay, onDownload: downloadAndPlay)
                Divider().overlay(Theme.Palette.hairline)
            }
        }
    }

    /// Tap on a not-downloaded episode → add the best cached version, refresh the library, and play.
    private func downloadAndPlay(_ row: DetailStore.EpisodeRowInfo) {
        guard let imdb = store.imdbID,
              let add = makeEpisodeDownload(imdb, row.season, row.number, store.originalLanguage) else { return }
        downloadingEpisodeID = row.id
        Task {
            await add.addBest()
            downloadingEpisodeID = nil
            if case let .added(info) = add.state,
               let req = store.playRequest(forAdded: info, season: row.season, number: row.number) {
                onSeasonAdded()       // refresh the library so the episode now appears as downloaded
                onPlay(req)
            }
        }
    }
}

/// One episode row: still + number/title (TMDB), synopsis, watched check. Downloaded → tap plays;
/// not-downloaded → "Not downloaded", tap downloads-then-plays (spinner while it works).
struct EpisodeRowView: View {
    let store: DetailStore
    let row: DetailStore.EpisodeRowInfo
    let isDownloading: Bool
    let onPlay: (PlaybackRequest) -> Void
    let onDownload: (DetailStore.EpisodeRowInfo) -> Void

    private var contentKey: String? {
        row.ownedEpisode.map { WatchKey.content(forShow: store.item, episode: $0) }
    }
    private var watch: WatchState? { contentKey.flatMap { store.watchState(forKey: $0) } }

    var body: some View {
        Button {
            if let ep = row.ownedEpisode, let src = row.ownedSource {
                onPlay(store.playRequest(source: src, episode: ep, label: label))
            } else {
                onDownload(row)
            }
        } label: {
            HStack(alignment: .top, spacing: Theme.Space.md) {
                still
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("\(row.number). \(row.meta?.name ?? "Episode \(row.number)")")
                            .font(Theme.Typo.headline()).foregroundStyle(Theme.Palette.textPrimary).lineLimit(1)
                        if watch?.finished == true {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.Palette.gold).font(.caption)
                        }
                    }
                    if let o = row.meta?.overview, !o.isEmpty {
                        Text(o).font(Theme.Typo.caption())
                            .foregroundStyle(Theme.Palette.textSecondary).lineLimit(2)
                    }
                    if !row.isDownloaded {
                        Text(isDownloading ? "Downloading\u{2026}" : "Not downloaded")
                            .font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                Spacer(minLength: 8)
                trailingIcon
            }
            .padding(.vertical, Theme.Space.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDownloading)
    }

    @ViewBuilder private var trailingIcon: some View {
        if isDownloading {
            ProgressView().tint(Theme.Palette.gold)
        } else if row.isDownloaded {
            Image(systemName: "play.circle.fill").foregroundStyle(Theme.Palette.gold)
        } else {
            Image(systemName: "arrow.down.circle").foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private var still: some View {
        RemoteImage(url: TMDBClient.imageURL(path: row.meta?.stillPath, size: "w300"))
        .frame(width: 124, height: 70)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip))
        .opacity(row.isDownloaded ? 1 : 0.55)     // dim not-downloaded episodes
    }

    private var label: String {
        "\(store.item.title) — S\(row.season)·E\(row.number)"
    }
}
