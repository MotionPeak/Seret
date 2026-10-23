import DebridCore
import DebridUI
import SwiftUI

/// Show title page (g3, as the movie page): full-bleed art under the glass bar, logo, metadata,
/// Play / Resume the next episode, the labelled glass circles, an expandable overview, ratings,
/// your rating, then the seasons and the FULL episode list for the selected season — downloaded
/// episodes play, the rest say "Not downloaded" and download-then-play on tap — and the rails.
struct ShowDetail: View {
    @Environment(AppSession.self) private var session
    @Environment(\.horizontalSizeClass) private var hSize
    let store: DetailStore
    /// Set as the page scrolls past the hero — the bar takes the title then (see DetailScreen).
    @Binding var heroScrolled: TitleScroll
    let onPlay: (PlaybackRequest) -> Void
    /// Builds a whole-season download engine for (imdbID, season, originalLanguage); injected so the
    /// view stays buildable without an AppSession. Returns nil when Stage 2 is unavailable.
    var makeSeasonDownload: (String, Int, String?) -> AddStore? = { _, _, _ in nil }
    /// Builds a single-episode download engine for (imdbID, season, episode, originalLanguage).
    var makeEpisodeDownload: (String, Int, Int, String?) -> AddStore? = { _, _, _, _ in nil }
    var onSeasonAdded: () -> Void = {}
    /// A "More Like This" poster was tapped — open that title's page, owned or not.
    /// The parent presents (see `SimilarRail`).
    var onOpenTitle: (MediaItem) -> Void = { _ in }
    /// "Remove from Library" — the parent confirms and performs it.
    var onRemoveTitle: () -> Void = {}
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
    private var regular: Bool { hSize == .regular }

    /// Re-keys the season-pack lookup whenever the resolved imdbID or selected season changes.
    private var seasonDownloadKey: String { "\(store.imdbID ?? "")#\(store.selectedSeason)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TitleHero(tmdbID: item.tmdbID, kind: .show, backdropPath: store.backdropPath,
                          posterFallback: item.posterPath, regular: regular) {
                    heroInfo
                } buttons: { trailer in
                    heroButtons(trailer)
                }
                sections
                    .titleColumn(regular: regular)
                    .padding(.top, regular ? Theme.Space.xxxl : Theme.Space.xxl)
                rails
                    .padding(.top, Theme.Space.xxxl)
                    .padding(.bottom, 48)
            }
        }
        // The art runs up under the status bar and the glass bar, as g3 draws it.
        .ignoresSafeArea(edges: .top)
        .titlePageScroll($heroScrolled)
        .background(CanvasBackground())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu { moreItems } label: { ToolbarGlassIcon(systemImage: "ellipsis") }
                    .tint(Theme.Palette.focus)
                    .accessibilityLabel("More")
            }
        }
        .sheet(isPresented: $showingMagnet) {
            if let tmdb = item.tmdbID {
                MagnetAddSheet(target: .init(
                    contentKey: DownloadKey.season(showTmdbID: tmdb, season: store.selectedSeason),
                    tmdbID: tmdb,
                    title: "\(item.title) Season \(store.selectedSeason)",
                    kind: .show, posterPath: item.posterPath))
                    .environment(session)
            }
        }
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
                                                  originalLanguage: store.originalLanguage,
                                                  runtimeMinutes: store.runtime)
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
                .compactMap { TMDBClient.imageURL(path: $0.meta?.stillPath, size: regular ? "w500" : "w300") }
            ImageMemoryCache.prefetch(stills)
        }
    }

    // MARK: Hero

    private var heroInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            TitleLogo(title: item.title, logoPath: store.logoPath,
                      settling: store.richState == .idle || store.richState == .loading,
                      maxWidth: regular ? 440 : 320, maxHeight: regular ? 130 : 104,
                      alignment: .bottomLeading,
                      font: .system(size: regular ? 48 : 38, weight: .heavy))
            TitleMetaRow(parts: metaParts)
        }
    }

    /// Year, seasons, ★ TMDB score, genres, then the original language.
    private var metaParts: [String] {
        var parts: [String] = []
        if let y = item.year { parts.append(String(y)) }
        let n = store.allSeasons.count
        if n > 0 { parts.append("\(n) Season\(n == 1 ? "" : "s")") }
        if let star = TitleMetaRow.rating(store.voteAverage) { parts.append(star) }
        if !store.genres.isEmpty { parts.append(store.genres.prefix(2).joined(separator: " · ")) }
        if let language = store.languageName { parts.append(language) }
        return parts
    }

    private func heroButtons(_ trailer: TrailerAction) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            playButton
                .frame(maxWidth: regular ? 380 : .infinity)
            TitleActionRow(regular: regular) {
                GlassActionButton(systemImage: "play.rectangle", title: "Trailer",
                                  accessibility: "Play Trailer", action: trailer.play)
                    .disabled(!trailer.isAvailable)
                GlassActionButton(systemImage: store.inMyList ? "checkmark" : "plus", title: "My List",
                                  isOn: store.inMyList,
                                  accessibility: store.inMyList ? "Remove from My List" : "Add to My List") {
                    Task { await store.toggleMyList(contentKey: store.item.id) }
                }
                if store.hasOwnedEpisodes(inSeason: store.selectedSeason) {
                    let watched = store.isSeasonWatched(store.selectedSeason)
                    GlassActionButton(systemImage: "checkmark", title: "Season Watched", isOn: watched,
                                      accessibility: watched
                                        ? "Mark \(SeasonOrder.label(store.selectedSeason)) Unwatched"
                                        : "Mark \(SeasonOrder.label(store.selectedSeason)) Watched") {
                        Task { await store.setSeasonWatched(!watched, season: store.selectedSeason) }
                    }
                }
                Menu { moreItems } label: {
                    GlassActionLabel(systemImage: "ellipsis", title: "More")
                }
                .buttonStyle(GlassPressStyle())
                .accessibilityLabel("More")
            }
        }
    }

    /// Play / Resume the next episode, full width. Nothing downloaded yet: Play still starts the
    /// show, finding and adding the first episode.
    @ViewBuilder private var playButton: some View {
        if let next = store.nextEpisode() {
            let resume = store.watchState(forKey: WatchKey.content(forShow: item, episode: next))
                .flatMap { $0.resumePosition }
            Button {
                onPlay(store.playRequest(source: next.source, episode: next,
                                         label: "\(item.title) — S\(next.season)·E\(next.number)"))
            } label: {
                Label(resume != nil ? "Resume S\(next.season) · E\(next.number)"
                                    : "Play S\(next.season) · E\(next.number)",
                      systemImage: "play.fill")
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .buttonStyle(PrimaryPillButtonStyle(fullWidth: true))
        } else if let target = store.nextEpisodeTarget() {
            Button {
                playEpisode(season: target.season, number: target.number,
                            id: "s\(target.season)e\(target.number)")
            } label: {
                Label(acquiring ? "Finding…" : "Play S\(target.season) · E\(target.number)",
                      systemImage: acquiring ? "hourglass" : "play.fill")
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .buttonStyle(PrimaryPillButtonStyle(fullWidth: true))
            // …and until the IMDb id has resolved. The engine cannot query an indexer without it, so
            // tapping earlier failed with "Not signed in to Real-Debrid" — a reason that is not
            // only unhelpful but untrue.
            .disabled(acquiring || acquisition == nil || store.imdbID == nil)
        }
    }

    /// The More menu — the same items from the action row's circle and the bar's ⋯.
    @ViewBuilder private var moreItems: some View {
        // The film page has offered this all along; an episode part-way through could only be
        // started over by dragging the player's bar back to 0:00.
        if let next = store.nextEpisode(),
           store.watchState(forKey: WatchKey.content(forShow: item, episode: next))?.resumePosition != nil {
            Button("Play S\(next.season) · E\(next.number) from Beginning", systemImage: "gobackward") {
                onPlay(store.playRequest(source: next.source, episode: next,
                                         label: "\(item.title) — S\(next.season)·E\(next.number)",
                                         fromStart: true))
            }
        }
        if store.hasOwnedEpisodes(inSeason: store.selectedSeason) {
            let watched = store.isSeasonWatched(store.selectedSeason)
            Button(watched ? "Mark Season Unwatched" : "Mark Season Watched",
                   systemImage: watched ? "checkmark.circle.fill" : "checkmark.circle") {
                Task { await store.setSeasonWatched(!watched, season: store.selectedSeason) }
            }
        }
        // The escape hatch for a season no indexer carries — old Israeli TV, anything off the
        // public trackers. Keyed to the selected season, as `SeasonDownloadButton` is: a pasted pack
        // is what these releases actually come as, and RD expands it into episodes when it lands.
        if item.tmdbID != nil {
            Button("Add \(SeasonOrder.label(store.selectedSeason)) by Magnet",
                   systemImage: "link.badge.plus") { showingMagnet = true }
        }
        // Only for a title that has files — see the movie page.
        if store.isInLibrary {
            Divider()
            Button("Remove from Library", systemImage: "trash", role: .destructive, action: onRemoveTitle)
        }
    }

    /// True while a release is being found or added.
    private var acquiring: Bool {
        switch acquisition?.phase {
        case .finding, .adding: true
        default: false
        }
    }

    // MARK: Sections

    private var sections: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxxl) {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                if let overview = store.overview, !overview.isEmpty {
                    ExpandableOverview(text: overview)
                }
                if !store.creatorRefs.isEmpty {
                    CreditNamesRow(label: "Created by", people: store.creatorRefs)
                }
                RatingsRow(ratings: store.ratings)
                WatchDatesLine(summary: store.watchSummary, since: store.historySince)
            }
            UserRatingRow(store: store)
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                TitleSectionHeader(title: "Episodes")
                seasonPicker
                SeasonDownloadButton(store: seasonStore, onAdded: onSeasonAdded,
                                     showTmdbID: store.item.tmdbID,
                                     season: store.selectedSeason,
                                     showTitle: store.item.title,
                                     posterPath: store.item.posterPath)
                episodeList
            }
        }
    }

    private var rails: some View {
        let margin = TitlePageMetrics.margin(regular: regular)
        return VStack(alignment: .leading, spacing: Theme.Space.xxxl) {
            // Gated on non-empty: the rails only appear once TMDB credits land, and they append
            // BELOW everything else, so they never resize content already on screen.
            if !store.cast.isEmpty { CastRail(cast: store.cast, margin: margin) }
            if !store.similar.isEmpty {
                SimilarRail(titles: store.similar, parentKind: .show,
                            onOpen: onOpenTitle, margin: margin)
            }
        }
    }

    /// Glass season pills; the selected one is white. Edge to edge, so a long run of seasons
    /// scrolls out past the margin instead of being cut at it.
    @ViewBuilder private var seasonPicker: some View {
        if store.allSeasons.count > 1 {
            let margin = TitlePageMetrics.margin(regular: regular)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(store.allSeasons, id: \.self) { n in
                        let selected = n == store.selectedSeason
                        Button { Task { await store.selectSeason(n) } } label: {
                            Text(SeasonOrder.label(n))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(selected ? Theme.Palette.onFocus : Theme.Palette.textPrimary)
                                .padding(.vertical, 9).padding(.horizontal, Theme.Space.lg)
                                .background { if selected { Capsule().fill(Theme.Palette.focus) } }
                                .modifier(SeasonPillGlass(selected: selected))
                        }
                        .buttonStyle(GlassPressStyle())
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)
            }
            .contentMargins(.horizontal, margin, for: .scrollContent)
            .padding(.horizontal, -margin)
        }
    }

    private var episodeList: some View {
        // Lazy: a season is up to two dozen rows, each with a still to fetch and decode, and a
        // non-lazy stack built every one of them before the first was on screen.
        LazyVStack(spacing: 0) {
            ForEach(store.episodes(forSeason: store.selectedSeason)) { row in
                EpisodeRowView(store: store, row: row, isDownloading: downloadingEpisodeID == row.id,
                               regular: regular,
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
    /// iPad: a bigger still and a third line of synopsis.
    var regular = false
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
                    Text("\(row.number). \(row.meta?.name ?? "Episode \(row.number)")")
                        .font(Theme.Typo.headline()).foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(2)
                    if let o = row.meta?.overview, !o.isEmpty {
                        Text(o).font(.system(size: 13))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .lineLimit(regular ? 3 : 2)
                    }
                    if let status = statusLine {
                        Text(status)
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
            // A tap resumes; this starts a part-watched episode over.
            if let ep = row.ownedEpisode, let src = row.ownedSource, watch?.resumePosition != nil {
                Button("Play from Beginning", systemImage: "gobackward") {
                    onPlay(store.playRequest(source: src, episode: ep, label: label, fromStart: true))
                }
            }
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
        Group {
            if isDownloading {
                ProgressView().tint(Theme.Palette.focus)
            } else if row.isDownloaded {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Palette.textPrimary)
            } else {
                Image(systemName: "arrow.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .frame(width: 34, height: 34)
        .background(Theme.Palette.glassFaint, in: Circle())
        .accessibilityHidden(true)
    }

    /// "Not downloaded" / "Downloading…", and the runtime when TMDB has one.
    private var statusLine: String? {
        var parts: [String] = []
        if let minutes = row.meta?.runtime, minutes > 0 { parts.append("\(minutes)m") }
        if isDownloading { parts.append("Downloading\u{2026}") }
        else if !row.isDownloaded { parts.append("Not downloaded") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A landscape still with the watch state ON it, as the Apple TV draws it: a white ✓ for a
    /// finished episode, a white line along the foot for one part-way through.
    private var still: some View {
        let width: CGFloat = regular ? 200 : 140
        // w500 on iPad: a 200pt still is 400–600 px wide there, and w300 upscaled went soft.
        return RemoteImage(url: TMDBClient.imageURL(path: row.meta?.stillPath,
                                                    size: regular ? "w500" : "w300")) {
            Theme.Palette.surface1.overlay {
                Image(systemName: "tv").foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .frame(width: width, height: width * 9 / 16)
        .overlay { if isWatched { Theme.Palette.artDim } }
        .overlay(alignment: .bottom) { progressBar }
        .overlay(alignment: .topTrailing) {
            if isWatched {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Palette.focus)
                    .background(Circle().fill(Theme.Palette.badgeBacking))
                    .padding(5)
                    .accessibilityLabel("Watched")
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
        .opacity(row.isDownloaded ? 1 : 0.55)     // dim not-downloaded episodes
    }

    @ViewBuilder private var progressBar: some View {
        if let w = watch, !w.finished, w.durationSeconds > 0, w.positionSeconds > 0 {
            ProgressLine(fraction: w.positionSeconds / w.durationSeconds, height: 3)
                .padding(.horizontal, 6).padding(.bottom, 6)
                .shadow(color: .black.opacity(0.5), radius: 3)
        }
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

/// An unselected season pill is glass; the selected one is plain white (drawn by the caller).
private struct SeasonPillGlass: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        if selected { content } else { content.seretGlass(in: Capsule()) }
    }
}
