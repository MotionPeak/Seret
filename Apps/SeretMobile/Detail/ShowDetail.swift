import DebridCore
import DebridUI
import SwiftUI

/// Show Detail: backdrop, title + meta, overview, Play-next, an all-seasons picker, and the full
/// episode list for the selected season. Every TMDB episode is shown — downloaded ones play, the
/// rest say "Not downloaded" and download-then-play on tap.
struct ShowDetail: View {
    @Environment(AppSession.self) private var session
    let store: DetailStore
    let onPlay: (PlaybackRequest) -> Void
    /// Builds a whole-season download engine for (imdbID, season, originalLanguage); injected so the
    /// view stays buildable without an AppSession. Returns nil when Stage 2 is unavailable.
    var makeSeasonDownload: (String, Int, String?) -> AddStore? = { _, _, _ in nil }
    /// Builds a single-episode download engine for (imdbID, season, episode, originalLanguage).
    var makeEpisodeDownload: (String, Int, Int, String?) -> AddStore? = { _, _, _, _ in nil }
    var onSeasonAdded: () -> Void = {}
    /// A "More Like This" poster was tapped — owned opens its Detail, new opens the Add flow.
    /// The parent presents (see `SimilarRail`).
    var onOpenTitle: (MediaItem) -> Void = { _ in }
    var onAddTitle: (SearchHit) -> Void = { _ in }
    /// Open the version list for ONE episode — the episode equivalent of a movie's "Versions".
    var onFindEpisodeVersions: (SearchHit, Int, Int) -> Void = { _, _, _ in }
    @State private var seasonStore: AddStore?
    /// The key `seasonStore` was built for. `.task(id:)` re-runs on every re-appearance, not only
    /// when the id changes — and coming back from the player is a re-appearance — so without this
    /// the indexer query ran again and the status line flashed back to "Checking…" over an answer
    /// it already had.
    @State private var loadedSeasonKey: String?
    @State private var downloadingEpisodeID: String?
    @State private var episodeError: String?
    /// Finds, adds and plays an episode you do not have — the same engine the movie page uses.
    @State private var acquisition: AcquisitionStore?
    @State private var showingMagnet = false
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
                if !store.creatorRefs.isEmpty {
                    CreditNamesRow(label: "By", people: store.creatorRefs)
                }
                RatingsRow(ratings: store.ratings)
                if let overview = store.overview {
                    Text(overview).font(Theme.Typo.body())
                        .foregroundStyle(Theme.Palette.textSecondary).lineLimit(4)
                }
                heroAction
                UserRatingRow(store: store)
                WatchDatesLine(summary: store.watchSummary, since: store.historySince)
                seasonPicker
                markSeasonButton
                SeasonDownloadButton(store: seasonStore, onAdded: onSeasonAdded,
                                     showTmdbID: store.item.tmdbID,
                                     season: store.selectedSeason,
                                     showTitle: store.item.title,
                                     posterPath: store.item.posterPath)
                magnetButton
                episodeList
                // Gated on non-empty: the rails only appear once TMDB credits land, and they append
                // BELOW everything else, so they never resize content already on screen.
                if !store.cast.isEmpty { CastRail(cast: store.cast) }
                if !store.similar.isEmpty {
                    SimilarRail(titles: store.similar, parentKind: .show,
                                onOpenOwned: onOpenTitle, onAddNew: onAddTitle)
                }
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
        .alert("Couldn\u{2019}t Play Episode", isPresented: Binding(
            get: { episodeError != nil }, set: { if !$0 { episodeError = nil } })) {
            Button("OK", role: .cancel) { episodeError = nil }
        } message: {
            Text(episodeError ?? "")
        }
        .task(id: seasonDownloadKey) {
            guard let imdb = store.imdbID, loadedSeasonKey != seasonDownloadKey else { return }
            loadedSeasonKey = seasonDownloadKey
            let s = makeSeasonDownload(imdb, store.selectedSeason, store.originalLanguage)
            seasonStore = s
            await s?.loadStreams()
        }
        // Rebuilt when the imdbID resolves — the engine cannot query the indexers without it.
        .task(id: store.imdbID) {
            acquisition = session.makeAcquisition(for: store.item, imdbID: store.imdbID,
                                                  originalLanguage: store.originalLanguage)
        }
        .onChange(of: acquisition?.phase) { _, phase in
            guard case let .ready(request) = phase else { return }
            onSeasonAdded()          // refresh the library so the episode now reads as downloaded
            acquisition?.reset()
            onPlay(request)
        }
        // On the container, not on WatchDatesLine: that view renders NOTHING until the summary it
        // is waiting for arrives, so hanging the load that produces it off a conditionally-empty
        // body makes it depend on SwiftUI keeping an empty view in the tree.
        .task { await store.loadWatchSummary() }
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
        // Creators are NOT folded in here any more — they are their own row of tappable names.
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder private var heroAction: some View {
        HStack(spacing: Theme.Space.md) {
            if let next = store.nextEpisode() {
                let resume = store.watchState(forKey: WatchKey.content(forShow: item, episode: next))
                    .flatMap { $0.resumePosition }
                Button {
                    onPlay(store.playRequest(source: next.source, episode: next,
                                             label: "\(item.title) — S\(next.season)·E\(next.number)"))
                } label: {
                    Label(resume != nil ? "Resume S\(next.season)·E\(next.number)"
                                        : "Play S\(next.season)·E\(next.number)",
                          systemImage: "play.fill")
                }
                .buttonStyle(GoldButtonStyle())
            } else if let target = store.nextEpisodeTarget() {
                // Nothing downloaded yet — Play still starts the show.
                Button {
                    playEpisode(season: target.season, number: target.number,
                                id: "s\(target.season)e\(target.number)")
                } label: {
                    Label(acquiring ? "Finding…" : "Play S\(target.season)·E\(target.number)",
                          systemImage: acquiring ? "hourglass" : "play.fill")
                }
                .buttonStyle(GoldButtonStyle())
                // …and until the IMDb id has resolved. The engine cannot query an indexer without it, so
                // tapping earlier failed with "Not signed in to Real-Debrid" — a reason that is not
                // only unhelpful but untrue.
                .disabled(acquiring || acquisition == nil || store.imdbID == nil)
            }
        }
    }

    /// True while a release is being found or added.
    private var acquiring: Bool {
        switch acquisition?.phase {
        case .finding, .adding: true
        default: false
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
                            .foregroundStyle(selected ? Theme.Palette.onGold : Theme.Palette.textSecondary)
                            .padding(.vertical, 7).padding(.horizontal, Theme.Space.lg)
                            .background(selected ? AnyShapeStyle(Theme.Palette.goldGradient)
                                                 : AnyShapeStyle(Theme.Palette.surface2), in: Capsule())
                    }
                }
            }
        }
    }

    /// One tap to mark the whole selected season watched/unwatched (its downloaded episodes).
    /// Hidden when the season has no downloaded episodes to mark.
    /// The escape hatch for a season no indexer carries — old Israeli TV, anything off the public
    /// trackers. Keyed to the selected season, matching `SeasonDownloadButton` above it: a pasted
    /// pack is what these releases actually come as, and RD expands it into episodes when it lands.
    @ViewBuilder private var magnetButton: some View {
        if let tmdb = item.tmdbID {
            Button { showingMagnet = true } label: {
                Label("Add by Magnet", systemImage: "link.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GhostButtonStyle())
            .sheet(isPresented: $showingMagnet) {
                MagnetAddSheet(target: .init(
                    contentKey: DownloadKey.season(showTmdbID: tmdb, season: store.selectedSeason),
                    tmdbID: tmdb,
                    title: "\(item.title) Season \(store.selectedSeason)",
                    kind: .show, posterPath: item.posterPath))
                    .environment(session)
            }
        }
    }

    @ViewBuilder private var markSeasonButton: some View {
        if store.hasOwnedEpisodes(inSeason: store.selectedSeason) {
            let watched = store.isSeasonWatched(store.selectedSeason)
            Button {
                Task { await store.setSeasonWatched(!watched, season: store.selectedSeason) }
            } label: {
                Label(watched ? "Mark Season Unwatched" : "Mark Season Watched",
                      systemImage: watched ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .buttonStyle(GhostButtonStyle())
        }
    }

    private var episodeList: some View {
        // Lazy: a season is up to two dozen rows, each with a still to fetch and decode, and a
        // non-lazy stack built every one of them before the first was on screen.
        LazyVStack(spacing: 0) {
            ForEach(store.episodes(forSeason: store.selectedSeason)) { row in
                EpisodeRowView(store: store, row: row, isDownloading: downloadingEpisodeID == row.id,
                               onPlay: onPlay, onDownload: downloadAndPlay,
                               onFindVersions: onFindEpisodeVersions)
                Divider().overlay(Theme.Palette.hairline)
            }
        }
    }

    /// Tap on a not-downloaded episode → find it, add it, play it.
    private func downloadAndPlay(_ row: DetailStore.EpisodeRowInfo) {
        playEpisode(season: row.season, number: row.number, id: row.id)
    }

    /// Acquire and play one episode, addressed by number so it works for a show you have not added
    /// at all. `.ready` is handled by the `onChange` above, which the hero's Play shares.
    private func playEpisode(season: Int, number: Int, id: String) {
        guard let acquisition else { return }
        // One at a time. Both taps shared ONE acquisition store, so a second tap overwrote the
        // first's search, whichever finished first cleared the spinner for both, and the `.ready`
        // the onChange presents could belong to either — tapping one episode and then another
        // could open the player on the wrong one. tvOS already disables its Play while a tap is in
        // flight; this is the same rule for a list row.
        guard downloadingEpisodeID == nil else { return }
        downloadingEpisodeID = id
        Task {
            await acquisition.playBest(.episode(season: season, number: number))
            downloadingEpisodeID = nil
            switch acquisition.phase {
            case .noneCached:
                await startEpisodeDownload(season: season, number: number, using: acquisition)
                acquisition.reset()
            case let .failed(message):
                episodeError = message
                acquisition.reset()
            default:
                break            // .ready is presented by onChange(of: acquisition?.phase)
            }
        }
    }

    /// Nothing cached for this episode — start a tracked Real-Debrid download instead of giving
    /// up. It cannot play now (it is still downloading), so progress surfaces on the Home
    /// "Downloading" rail rather than opening the player.
    private func startEpisodeDownload(season: Int, number: Int,
                                      using acquisition: AcquisitionStore) async {
        let candidates = await acquisition.uncachedCandidates(
            .episode(season: season, number: number))
        guard !candidates.isEmpty, let tmdb = store.item.tmdbID else {
            episodeError = "No version of this episode is available to download."
            return
        }
        await session.downloadStore?.request(
            contentKey: DownloadKey.episode(showTmdbID: tmdb, season: season, number: number),
            tmdbID: tmdb,
            title: "\(store.item.title) S\(season)E\(number)",
            kind: .show, candidates: candidates, posterPath: store.item.posterPath)
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
    var onFindVersions: (SearchHit, Int, Int) -> Void = { _, _, _ in }

    /// Keyed by season/episode NUMBER, not by the file you own: an episode you have watched but
    /// never downloaded still has watch state, and this row still has to show it.
    private var contentKey: String {
        WatchKey.content(forShow: store.item, season: row.season, number: row.number)
    }
    private var watch: WatchState? { store.watchState(forKey: contentKey) }
    private var isWatched: Bool { watch?.finished == true }

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
        // Long-press to mark watched — including an episode you have not downloaded, which you may
        // well have seen elsewhere.
        .contextMenu {
            Button(isWatched ? "Mark Unwatched" : "Mark Watched",
                   systemImage: isWatched ? "checkmark.circle.fill" : "checkmark.circle") {
                Task { await store.setWatched(!isWatched, contentKey: contentKey,
                                              source: row.ownedSource) }
            }
            // The other copies of this episode you already own — only when there IS a choice, so
            // the common single-copy episode keeps a one-item menu.
            if let ep = row.ownedEpisode, row.hasAlternateVersions {
                Menu("Versions", systemImage: "square.stack.3d.up") {
                    ForEach(row.ownedVersions, id: \.self) { src in
                        Button(versionLabel(src)) {
                            onPlay(store.playRequest(source: src, episode: ep, label: label))
                        }
                    }
                }
            }
            if let hit = showHit {
                Button("Find Other Versions", systemImage: "magnifyingglass") {
                    onFindVersions(hit, row.season, row.number)
                }
            }
        }
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

    /// The show, as the Add pipeline wants it. Needs a TMDB id to search.
    private var showHit: SearchHit? {
        guard let tmdb = store.item.tmdbID else { return nil }
        return SearchHit(result: TMDBSearchResult(
            id: tmdb, title: nil, name: store.item.title, releaseDate: nil, firstAirDate: nil,
            posterPath: store.item.posterPath, overview: nil, voteAverage: nil), kind: .show)
    }

    /// Resolution · source · size — enough to tell two copies apart in a menu.
    private func versionLabel(_ src: MediaSource) -> String {
        var parts = [src.parsed.resolution, src.parsed.source].compactMap { $0 }
        if let bytes = src.sizeBytes {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
        }
        if parts.isEmpty { parts = ["Version"] }
        return parts.joined(separator: " · ")
    }

    private var label: String {
        "\(store.item.title) — S\(row.season)·E\(row.number)"
    }
}
