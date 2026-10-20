import DebridCore
import DebridUI
import SwiftUI

/// Show Detail, Plex-style: the title's ultrablur backdrop behind the whole page; on the left the
/// logo, metadata, overview and the action row (Resume/Play-next pill, then circular actions);
/// below them the season pills, the selected season's episode cards, and the rails.
struct ShowDetailView: View {
    let store: DetailStore
    var onRemove: () -> Void = {}
    /// Builds a whole-season download engine for (imdbID, season, originalLanguage); injected so the
    /// Preview (which has no AppSession) stays buildable. Returns nil when Stage 2 is unavailable.
    var makeSeasonDownload: (String, Int, String?) -> AddStore? = { _, _, _ in nil }
    var onSeasonAdded: () -> Void = {}
    /// A not-downloaded episode was selected → download-then-play (handled by DetailView).
    var onDownloadEpisode: (DetailStore.EpisodeRowInfo) -> Void = { _ in }
    /// Play an episode by number — the hero's Play on a show with nothing downloaded.
    var onPlayEpisode: (Int, Int) -> Void = { _, _ in }
    var downloadingEpisodeID: String? = nil
    @State private var seasonStore: AddStore?
    /// The season button has been pressed for the season on screen — it stays put until the
    /// season changes, whatever the library says about the season meanwhile.
    private var seasonButtonInUse: Bool {
        switch seasonStore?.state {
        case .adding, .added, .addFailed: return true
        default: return false
        }
    }
    /// The key `seasonStore` was built for. `.task(id:)` re-runs on every re-appearance, not only
    /// when the id changes — and coming back from the player is a re-appearance — so without this
    /// the indexer query ran again and the status line flashed back to "Checking…" over an answer
    /// it already had.
    @State private var loadedSeasonKey: String?
    /// Which season pill has focus — moving across them switches the season live (no press).
    @FocusState private var focusedSeason: Int?
    /// Which action has focus. `.defaultFocus($focus, .play)` forces INITIAL focus onto the Play
    /// CTA: tvOS sets no initial focus on a page like this one, and without it the remote goes dead
    /// (you can't move or select anything). The other cases let the action row animate its layout
    /// as a circle opens into a pill, so its neighbours slide rather than jump.
    private enum Field: Hashable { case play, fromStart, more }
    @FocusState private var focus: Field?
    /// Scrolled down into the seasons and rails: the art recedes (the trailer plays on).
    @State private var scrolledAway = false
    @State private var trailerURL: URL?
    @State private var expandTrailer = false
    private var item: MediaItem { store.item }

    /// Re-keys the season-pack lookup whenever the resolved imdbID or the selected season changes.
    private var seasonDownloadKey: String { "\(store.imdbID ?? "")#\(store.selectedSeason)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 32) {
                    hero.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 24)
                    seasonPicker
                    // One full-width section: UP from an episode card scrolled to the right had
                    // nothing above it within these shrink-wrapped buttons, so it skipped them and
                    // landed on a season pill.
                    HStack(spacing: 20) {
                        markSeasonButton
                        // A season you already have every episode of has nothing to download — the
                        // button would only add a duplicate torrent. Unless it is THIS button that
                        // just made the season complete: removing it then took the focused control
                        // out from under the viewer the moment the library caught up.
                        if !store.isSeasonFullyOwned(store.selectedSeason) || seasonButtonInUse {
                            SeasonDownloadButton(store: seasonStore, onAdded: onSeasonAdded,
                                                 showTmdbID: store.item.tmdbID,
                                                 season: store.selectedSeason,
                                                 showTitle: store.item.title,
                                                 posterPath: store.item.posterPath)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focusSection()
                    episodeList
                }
                .padding(.horizontal, DetailLayout.inset)
                .padding(.top, DetailLayout.topPadding)
                VStack(alignment: .leading, spacing: FocusBrowseLayout.railSpacing) {
                    // Gated on non-empty: the rail only ever appears once TMDB credits land, and it
                    // appends BELOW everything else, so it never resizes content already on screen.
                    if !store.cast.isEmpty { CastRail(cast: store.cast) }
                    if !store.similar.isEmpty {
                        SimilarRail(titles: store.similar, parentKind: .show)
                    }
                }
                .padding(.horizontal, DetailLayout.railInset)
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
        }
        .onScrollGeometryChange(for: Bool.self) { [wasAway = scrolledAway] geo in
            DetailLayout.scrolledAway(geo, wasAway: wasAway)
        } action: { _, away in
            scrolledAway = away
        }
        .defaultFocus($focus, .play)
        .background {
            TrailerHero(tmdbID: item.tmdbID, kind: .show, backdropPath: pageBackdrop,
                        resolvedURL: $trailerURL, paused: expandTrailer, receded: scrolledAway)
        }
        .fullScreenCover(isPresented: $expandTrailer) {
            if let u = trailerURL { FullScreenTrailer(url: u) }
        }
        .task(id: seasonDownloadKey) {
            guard let imdb = store.imdbID, loadedSeasonKey != seasonDownloadKey else { return }
            loadedSeasonKey = seasonDownloadKey
            let s = makeSeasonDownload(imdb, store.selectedSeason, store.originalLanguage)
            seasonStore = s
            await s?.loadStreams()
        }
        // Warm the episode stills as soon as the season's metadata lands, so the cards aren't grey
        // while you scroll down to them. Re-fires when the season changes or its episodes load.
        .task(id: "\(store.selectedSeason)#\(store.episodeMeta[store.selectedSeason]?.count ?? 0)") {
            ImageMemoryCache.prefetch(
                store.episodes(forSeason: store.selectedSeason)
                    .compactMap { TMDBClient.imageURL(path: $0.meta?.stillPath, size: "w300") })
        }
    }

    /// The backdrop, or — once the details have answered without one — the poster. See
    /// `MovieDetailView.pageBackdrop`.
    private var pageBackdrop: String? {
        if let backdrop = store.backdropPath { return backdrop }
        switch store.richState {
        case .loaded, .failed: return item.posterPath
        default: return nil
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailTitleArt(title: item.title, logoPath: store.logoPath, settling: settling)
            DetailMetaRow(items: metaItems, ratings: store.ratings)
                .padding(.top, 22)
            if let overview = store.overview {
                ExpandableOverview(text: overview, title: item.title, lineLimit: 3,
                                   maxWidth: DetailLayout.textWidth)
                    .padding(.top, 22)
            }
            heroActions
                .padding(.top, 34)
            VStack(alignment: .leading, spacing: 22) {
                UserRatingRow(store: store)
                WatchDatesLine(summary: store.watchSummary, since: store.historySince)
                if !store.creatorRefs.isEmpty {
                    CreditNamesRow(label: "Created by", people: store.creatorRefs)
                }
            }
            .padding(.top, 40)
        }
        // On the container, not on WatchDatesLine: that view renders NOTHING until the summary it
        // is waiting for arrives, so hanging the load that produces it off a conditionally-empty
        // body makes it depend on SwiftUI keeping an empty view in the tree.
        .task { await store.loadWatchSummary() }
    }

    /// The details (and with them the logo) are still on their way.
    private var settling: Bool {
        switch store.richState {
        case .idle, .loading: return item.tmdbID != nil
        default: return false
        }
    }

    private var metaItems: [String] {
        DetailMetaRow.items(year: item.year, runtime: nil, seasons: store.allSeasons.count,
                            vote: store.voteAverage, language: store.languageName,
                            genres: store.genres)
    }

    @ViewBuilder private var heroActions: some View {
        HStack(spacing: 20) {
            if let next = store.nextEpisode() {
                let resume = store.watchState(forKey: WatchKey.content(forShow: item, episode: next))
                    .flatMap { $0.resumePosition }
                NavigationLink(value: store.playRequest(
                    source: next.source, episode: next,
                    label: "\(item.title) — S\(next.season)·E\(next.number)")) {
                    Label(resume != nil ? "Resume S\(next.season)·E\(next.number)"
                                        : "Play S\(next.season)·E\(next.number)",
                          systemImage: "play.fill")
                }
                .buttonStyle(SeretActionButtonStyle(prominent: true,
                                                    minHeight: ExpandingIconButtonStyle.diameter))
                .focused($focus, equals: .play)

                // The film page has offered this all along; an episode part-way through could only
                // be started over by scrubbing back to 0:00 inside the player.
                if resume != nil {
                    NavigationLink(value: store.playRequest(
                        source: next.source, episode: next,
                        label: "\(item.title) — S\(next.season)·E\(next.number)", fromStart: true)) {
                        Label("From Start", systemImage: "gobackward")
                    }
                    .buttonStyle(ExpandingIconButtonStyle())
                    .focused($focus, equals: .fromStart)
                }
            } else {
                // Nothing downloaded yet — Play still starts the show. ONE button whatever it says,
                // and always there: it is what `.defaultFocus` lands on, and the action row starts
                // off-screen, so without it the page took no focus at all and the remote went dead
                // — as it did for a show with nothing aired yet, which has no episode to play.
                // Busy in the label, never `.disabled` — a disabled button loses tvOS focus. The
                // page ignores a second press while one is under way (`DetailView.playEpisode`).
                let target = store.nextEpisodeTarget()
                Button {
                    if let target {
                        onPlayEpisode(target.season, target.number)
                    } else {
                        switch store.episodesState(forSeason: store.selectedSeason) {
                        case .failed: Task { await store.retrySeason() }
                        // Only once the list says nothing has aired: while it loads the button
                        // reads "Play", and a press then opened the trailer full-screen.
                        case .loaded: if trailerURL != nil { expandTrailer = true }
                        case .loading: break                 // early — Play is on its way
                        }
                    }
                } label: {
                    if let target {
                        Label(downloadingEpisodeID == nil
                              ? "Play S\(target.season)·E\(target.number)" : "Finding a version…",
                              systemImage: downloadingEpisodeID == nil ? "play.fill" : "hourglass")
                    } else {
                        Label(notYetTitle, systemImage: notYetIcon)
                    }
                }
                .buttonStyle(SeretActionButtonStyle(prominent: true,
                                                    minHeight: ExpandingIconButtonStyle.diameter))
                .focused($focus, equals: .play)
            }

            // Trailer + destructive Remove tucked off the primary path.
            Menu {
                if trailerURL != nil {
                    Button { expandTrailer = true } label: {
                        Label("Trailer", systemImage: "play.rectangle.fill")
                    }
                }
                if !item.seasons.isEmpty {
                    Button(role: .destructive) { onRemove() } label: {
                        Label("Remove from Library", systemImage: "trash")
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .buttonStyle(ExpandingIconButtonStyle())
            .focused($focus, equals: .more)
        }
        // A focused circle opens into a pill and its neighbours make room. Animated on the ROW, so
        // they slide in step with the pill's own growth instead of jumping to their new places.
        .animation(Theme.Anim.focus, value: focus)
        // Each horizontal row is one target for vertical travel. Wide scrolling rows sat above and
        // below narrow left-aligned buttons, so a card scrolled to the right had nothing above it
        // and UP was a dead press. (`.focusSection()` widens a target; it does NOT trap focus.)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    /// What the primary button says with no episode to play: the season's episodes are still on
    /// their way (or failed — pressing asks again), or nothing listed has aired yet.
    private var notYetTitle: String {
        switch store.episodesState(forSeason: store.selectedSeason) {
        case .loading, .failed: return "Play"
        case .loaded: break
        }
        if let date = store.nextAirDate {
            // An air DATE, held as midnight UTC: printed in the device's zone it was the day
            // before anywhere west of Greenwich.
            var day = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
            day.timeZone = TimeZone(identifier: "UTC") ?? .gmt
            return "Premieres \(date.formatted(day))"
        }
        return trailerURL != nil ? "Trailer" : "Coming Soon"
    }

    private var notYetIcon: String {
        switch store.episodesState(forSeason: store.selectedSeason) {
        case .loading, .failed: return "play.fill"
        case .loaded: return trailerURL != nil ? "play.rectangle.fill" : "calendar"
        }
    }

    @ViewBuilder private var seasonPicker: some View {
        if store.allSeasons.count > 1 {   // a single-season show needs no picker (and avoids a lone chip)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(store.allSeasons, id: \.self) { number in
                        Button(SeasonOrder.label(number)) { Task { await store.selectSeason(number) } }
                            .buttonStyle(SeretPillStyle(selected: number == store.selectedSeason))
                            .focused($focusedSeason, equals: number)
                    }
                }
                .padding(.horizontal, Theme.Layout.contentMargin)    // align with the page + leave room for the focus scale,
            }
            .padding(.horizontal, -Theme.Layout.contentMargin)       // while the ScrollView runs edge-to-edge so a focused
                                                     // pill's scaled side isn't clipped at the row edge.
            // Switch only while GLIDING across the pills. Arriving in the row from below (an episode
            // card, the stars) or above lands on whichever pill is geometrically nearest — rarely the
            // selected one — and that silently loaded another season: rate a show 8/10, press down
            // and the season under star 8 opened. Arriving is not a choice; Select still is.
            .onChange(of: focusedSeason) { old, new in
                guard let new, old != nil, new != store.selectedSeason else { return }
                Task { await store.selectSeason(new) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
        }
    }

    /// One press to mark the whole selected season watched/unwatched (its downloaded episodes).
    /// Hidden when the season has no downloaded episodes to mark.
    @ViewBuilder private var markSeasonButton: some View {
        if store.hasOwnedEpisodes(inSeason: store.selectedSeason) {
            let watched = store.isSeasonWatched(store.selectedSeason)
            Button {
                Task { await store.setSeasonWatched(!watched, season: store.selectedSeason) }
            } label: {
                Label(watched ? "Mark Season Unwatched" : "Mark Season Watched",
                      systemImage: watched ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .buttonStyle(SeretActionButtonStyle())
        }
    }

    private var episodeList: some View {
        let rows = store.episodes(forSeason: store.selectedSeason)
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 36) {
                if rows.isEmpty {
                    switch store.episodesState(forSeason: store.selectedSeason) {
                    case .loading:
                        // Hold the row's HEIGHT with skeletons while the season loads — an empty row
                        // collapses to nothing and snaps the page's scroll to the top (the B/D jump).
                        ForEach(0..<5, id: \.self) { _ in EpisodePlaceholderCard() }
                    case .loaded:
                        // Skeletons here would mean "loading" forever: TMDB lists the season, with
                        // nothing in it yet.
                        EpisodeNoticeCard(message: "No episodes in this season yet.")
                    case .failed:
                        EpisodeNoticeCard(message: "Couldn\u{2019}t load this season\u{2019}s episodes.",
                                          retry: { Task { await store.retrySeason() } },
                                          retrying: store.retryingSeason == store.selectedSeason)
                    }
                } else {
                    ForEach(rows) { row in
                        EpisodeRow(store: store, row: row,
                                   isDownloading: downloadingEpisodeID == row.id,
                                   onDownload: onDownloadEpisode)
                    }
                }
            }
            .padding(.vertical, 24)      // room for the still's lift, ring and shadow
            .padding(.horizontal, Theme.Layout.contentMargin)    // align with the page + room for the focus scale at the edges
        }
        // The lift and ring draw past the row's own bounds rather than being cut at them.
        .scrollClipDisabled()
        .padding(.horizontal, -Theme.Layout.contentMargin)       // ScrollView runs edge-to-edge so a focused card doesn't clip
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
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
