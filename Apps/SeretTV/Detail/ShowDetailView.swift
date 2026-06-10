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
    /// Which season pill has focus — moving across them switches the season live (no press).
    @FocusState private var focusedSeason: Int?
    /// Forces INITIAL focus onto the Play CTA. Without it, the action row sits below the tall hero
    /// (off-screen on open) and tvOS sets no initial focus at all — the remote goes dead (you can't
    /// move or select anything). `.defaultFocus` puts focus on Play and scrolls it into view.
    private enum Field: Hashable { case play }
    @FocusState private var initialFocus: Field?
    @State private var trailerURL: URL?
    @State private var expandTrailer = false
    private var item: MediaItem { store.item }

    /// Re-keys the season-pack lookup whenever the resolved imdbID or the selected season changes.
    private var seasonDownloadKey: String { "\(store.imdbID ?? "")#\(store.selectedSeason)" }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TrailerHero(tmdbID: item.tmdbID, kind: .show,
                            backdropPath: store.backdropPath, posterFallback: item.posterPath,
                            resolvedURL: $trailerURL)
                VStack(alignment: .leading, spacing: 32) {
                    hero.frame(maxWidth: .infinity, alignment: .leading)
                    seasonPicker
                    SeasonDownloadButton(store: seasonStore, onAdded: onSeasonAdded)
                    episodeList
                }
                .padding(60)
            }
        }
        .defaultFocus($initialFocus, .play)
        .background(CanvasBackground())
        .fullScreenCover(isPresented: $expandTrailer) {
            if let u = trailerURL { FullScreenTrailer(url: u) }
        }
        .task(id: seasonDownloadKey) {
            guard let imdb = store.imdbID else { return }
            let s = makeSeasonDownload(imdb, store.selectedSeason, store.originalLanguage)
            seasonStore = s
            await s?.loadStreams()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(item.title).screenTitle()
            Text(metaLine).calloutText().foregroundStyle(Theme.Palette.textSecondary)
            RatingsRow(ratings: store.ratings)
            if let overview = store.overview {
                Text(overview).bodyText().frame(maxWidth: 1100, alignment: .leading).lineLimit(4)
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
        HStack(spacing: 16) {
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
                .buttonStyle(SeretActionButtonStyle(prominent: true))
                .focused($initialFocus, equals: .play)
            }
            if trailerURL != nil {
                Button { expandTrailer = true } label: {
                    Label("Trailer", systemImage: "play.rectangle.fill")
                }
                .buttonStyle(SeretActionButtonStyle())
            }
            Button(role: .destructive) { onRemove() } label: {
                Label("Remove from Library", systemImage: "trash")
            }
            .buttonStyle(SeretActionButtonStyle(destructive: true))
        }
        // A focusable Trailer button (above) opens the full-screen trailer. We do NOT use
        // `.onMoveCommand` here — on tvOS it captures directional input for the focused subtree and
        // blocks the focus engine, which trapped focus on this row (couldn't reach the episodes).
    }

    @ViewBuilder private var seasonPicker: some View {
        if store.allSeasons.count > 1 {   // a single-season show needs no picker (and avoids a lone chip)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(store.allSeasons, id: \.self) { number in
                        Button("Season \(number)") { Task { await store.selectSeason(number) } }
                            .buttonStyle(SeretPillStyle(selected: number == store.selectedSeason))
                            .focused($focusedSeason, equals: number)
                    }
                }
                .padding(.horizontal, 60)    // align with the page + leave room for the focus scale,
            }
            .padding(.horizontal, -60)       // while the ScrollView runs edge-to-edge so a focused
                                             // pill's scaled side isn't clipped at the row edge.
            .onChange(of: focusedSeason) { _, new in
                if let new, new != store.selectedSeason { Task { await store.selectSeason(new) } }
            }
        }
    }

    private var episodeList: some View {
        let rows = store.episodes(forSeason: store.selectedSeason)
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 30) {
                if rows.isEmpty {
                    // Hold the row's HEIGHT with skeletons while the season loads — an empty row
                    // collapses to nothing and snaps the page's scroll to the top (the B/D jump).
                    ForEach(0..<5, id: \.self) { _ in EpisodePlaceholderCard() }
                } else {
                    ForEach(rows) { row in
                        EpisodeRow(store: store, row: row,
                                   isDownloading: downloadingEpisodeID == row.id,
                                   onDownload: onDownloadEpisode)
                    }
                }
            }
            .padding(.vertical, 16)      // room for the focus lift
            .padding(.horizontal, 60)    // align with the page + room for the focus scale at the edges
        }
        .padding(.horizontal, -60)       // ScrollView runs edge-to-edge so a focused card doesn't clip
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
