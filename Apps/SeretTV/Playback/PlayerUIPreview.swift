#if DEBUG
import SwiftUI
import DebridUI
import DebridCore

/// DEBUG-only visual harnesses for player overlays. The tvOS simulator accepts no reliable
/// synthesized input, so the live player screen can't be driven there; these boot straight to a
/// target view so its layout can be screenshot-verified.
///
/// Launch with `-uiPreview <target>`, where target is:
///   - `scrubbar`  — the transport bar in each of its states, the last one skipping (the badge
///     counting up above the knob)
///   - `settings`  — the settings side sheet on Subtitles, with grouped subtitle tracks
///   - `playercontrols` — the REAL `PlayerView` over a still, paused, the control row open with
///     Subtitles focused: top line, bar riding up, the row. `playercontrolsshow`: the same on an
///     episode (episode title line, an Episodes button, no year)
///   - `playersheet` — the real player with the settings sheet open on Subtitles (Menu goes back
///     to the row). `playersheetaudio`: on Audio
///   - `playerpaused` — the real player paused with nothing open: bar, top line, the centre glyph.
///     `playerpausedshow`: the same on an episode, with the "⌃ Episodes" peek above the bar
///   - `playerskip` — the real player playing while ±10s skips keep landing: the badge riding the
///     knob as it accumulates (+10s … +1:10 …)
///   - `playerupnext` — an episode in its last seconds: the Up Next bar (Play Now focused) above
///     the scrub bar, which the open reveals
///   - `playerloading` / `playererror` — the real player before its first frame, and after a
///     source that could not be opened (Retry focused). `playererrorrow`: the open fails while the
///     control row is up — the row must go, leaving Retry focused and nothing hidden behind it
///     `playererrorbrowser`: the same failure with the subtitle browser up — the browser (drawn
///     above the error) must close, leaving Retry focused
///   - `playerupnextbuffering` — Up Next up, then playback stalls: the small spinner rides in the
///     Up Next bar; the scrub bar stays down and Up Next does not move
///   - `subtitles` — the full subtitle browser with ranked, badged results
///   - `subtitlesfailed` — the same browser after a pick that could not be honoured
///   - `detail`    — the Movie Detail page with a rating-capable stub store (no art: the title
///     stands in for the logo, the backdrop is the canvas)
///   - `detailart` — an owned film with real backdrop + logo, resume, versions, cast, franchise
///     and More Like This: the Plex-style title page's composition check
///   - `showdetail` — an owned show with real backdrop, two seasons, watched / part-watched
///     episode cards, cast and More Like This
///   - `unpremiered` — the page of a show whose every listed episode airs in 2099: no episode to
///     play, so the screenshot says what holds the page's focus
///   - `downloadfinish` — a film page whose requested download finishes 25 s in: the library takes
///     it and the page becomes the owned page. Focus the download button first (Down from Play)
///     and the screenshot after says where focus went
///   - `sidemenu`  — the side menu EXPANDED over a stand-in page
///   - `sidemenucollapsed` — the same menu at rest, for an A/B of the two states
///   - `sidemenucollapsedfocus` — at rest with a row focused (the white circle)
///   - `sidemenulive` — the menu driven by the shell's open/close rules, for a remote walkthrough
///   - `opensubtitles` — the OpenSubtitles pairing card: QR, LAN address, keyboard fallback
///   - `gridfade`  — a pre-scrolled grid under a pinned header over a real backdrop, for tuning
///     the top fade (it must dissolve into the art, not a flat bar)
///   - `person`    — the person page: header, As Actor / As Director, ranked credits, the focused
///     credit's backdrop
///   - `autosync` / `autosyncdone` / `autosyncfailed` — the subtitle-sync bar over the picture
///   - `manualsync` / `manualsyncpressed` — sync-to-a-line, before and after the press
///   - `home`      — the Home screen whole: hero, Continue Watching rail, Recently Added grid
///   - `watchlist` — the Letterboxd watchlist page with a partner (Noga): every row — In Your
///     Library, Recently Added, Highest Rated, You Both, Noga's Picks, genres, Short Ones,
///     Classics, Not Matched — over real TMDB details and art
///   - `watchlistpartner` — the same page with the partner's list unreadable AND a removal that
///     did not reach Letterboxd: both lines stacked under the header pills, never over the rows
///   - `watchlistslow` — a first visit with a slow TMDB (3 s a film): the header fills in as
///     batches land, the rows only change once the pass is over — nothing moves under focus
///   - `spin` — Surprise Me's Cover Flow reel, mid-turn and landed on Whiplash with its backdrop
///   - `spinnoart` — the same landing with no TMDB art: text title, plain background
///   - `serverprobe` — can this Apple TV actually reach SeretServer? Names ATS and local-network
///     refusals separately from an unreachable server
///   - `letterboxd` — the Settings Letterboxd section with the import blocked, between two rows
///     that DO take focus, so "can the remote reach it?" is answerable from a screenshot
///   - `letterboxdrating` / `letterboxdrerating` — the post-credits rating prompt, unrated and
///     already rated 7. Prints what the press produced, so a screenshot answers it
///   - `styles` / `stylesplain` / `stylescard` — every design-system style on one page, focus on
///     an expanding icon button, a plain action pill or a poster (see `StyleGalleryPreview`)
///   - `plexrails` — a `FocusBrowsePage` with three rails of real TMDB art: the preview header
///     (logo, meta, synopsis), the ultrablur backdrop, focus on the first poster. `plexrailsnoart`
///     starts (via the page's focus hook) on a mid-rail tile with no art and a Hebrew title;
///     `plexrailsinsert` starts in the second rail and inserts a rail above it 4 s in
///     (`plexrailsinsertearly`: 300ms after focus lands, inside the initial scroll's settle window) (see
///     `PlexRailsPreview`)
///   - `browse` — the Movies page (one stack of rows: For You, Trending, New, Top Rated, a row
///     per genre) on fixture Discover rows that arrive progressively (one 4 s late, the rest
///     behind it); `browseinsert` adds a For You row ABOVE the others 9 s in (see
///     `BrowseScreenPreview`). A genre row's See All pushes that genre's grid on fixture titles.
///     `browsefailed`: every row fails — the failed row, whose Retry must keep focus.
///     `browsetrendingfails`: Trending fails (2.5 s in) — its row is dropped
///   - `library` — My Library on a fixture library (real art) with two downloads in flight, focus
///     on the Movies pill, the backdrop following focus into the grid (see `MyLibraryScreenPreview`).
///     `librarydownloadends` / `librarydownloadstarts`: the strip goes / appears 14 s in — walk
///     down to a lower row first; the focused cell must stay where it is.
///     `librarydownloadfocusedends`: the focused card's download finishes while another carries on
///     (12 s), then the last one (22 s) — see `MyLibraryScreenPreview`
///   - `search` — Search with "dune" already typed, fixture results, real art (see
///     `SearchScreenPreview`)
///
/// Not compiled into release builds.
struct PlayerUIPreview: View {
    let target: String

    var body: some View {
        switch target {
        // Sign-in, splash, profiles, Settings and the watchlist toast — see `ScreensUIPreview`.
        case _ where ScreensUIPreview.targets.contains(target): ScreensUIPreview(target: target)
        case "settings":   SettingsPanelPreview()
        case "playercontrols":      PlayerChromePreview(overlay: .controls, paused: true)
        case "playercontrolsshow":  PlayerChromePreview(overlay: .controls, paused: true, show: true)
        case "playersheet":         PlayerChromePreview(overlay: .sheet(.subtitles), paused: true)
        case "playersheetaudio":    PlayerChromePreview(overlay: .sheet(.audio), paused: true)
        case "playerpaused":        PlayerChromePreview(overlay: .none, paused: true)
        case "playerpausedshow":    PlayerChromePreview(overlay: .none, paused: true, show: true)
        case "playerskip":          PlayerChromePreview(overlay: .none, skipping: true)
        case "playerupnext":        PlayerChromePreview(overlay: .none, show: true, nearEnd: true)
        case "playerloading":       PlayerChromePreview(overlay: .none, stage: .loading)
        case "playererror":         PlayerChromePreview(overlay: .none, stage: .failed)
        case "playererrorrow":      PlayerChromePreview(overlay: .controls, stage: .failed)
        case "playererrorbrowser":  PlayerChromePreview(overlay: .subtitleBrowser, stage: .failed)
        case "playerupnextbuffering": PlayerChromePreview(overlay: .none, show: true, nearEnd: true,
                                                          bufferingAtEnd: true)
        case "subtitles":  SubtitleBrowserPreview()
        case "subtitlesfailed": SubtitleBrowserPreview(failing: true)
        case "inputprobe": InputProbePreview()
        case "detail":     MovieDetailPreview()
        case "downloadfinish": DownloadFinishPreview()
        case "unpremiered":    UnpremieredShowPreview()
        case "detailwatchlisted": MovieDetailPreview(onWatchlist: true)
        case "detailart":  MovieDetailArtPreview()
        case "showdetail": ShowDetailArtPreview()
        case "sidemenu":            SideMenuPreview(startExpanded: true)
        case "sidemenucollapsed":   SideMenuPreview(startExpanded: false)
        case "sidemenucollapsedfocus": SideMenuPreview(startExpanded: false, focusMenu: true)
        case "sidemenulive":        SideMenuPreview(live: true)
        case "opensubtitles":       OpenSubtitlesPreview()
        case "gridfade":            GridTopFadePreview()
        case "person":              PersonScreenPreview()
        case "episodeversions":     EpisodeVersionsPreview()
        case "episodenotice":       EpisodeNoticePreview()
        case "versions":            VersionListPreview()
        case "autosync":            AutoSyncBarPreview(mood: .measuring)
        case "autosyncdone":        AutoSyncBarPreview(mood: .synced)
        case "autosyncfailed":      AutoSyncBarPreview(mood: .failed)
        case "manualsync":          ManualSyncPanelPreview(pressed: false)
        case "manualsyncpressed":   ManualSyncPanelPreview(pressed: true)
        case "home":                HomeScreenPreview()
        case "homefailed":          HomeScreenPreview(failure: "Couldn't reach Real-Debrid. Check the connection and try again.")
        case "homedownloading":     HomeScreenPreview(downloading: true)
        case "homedownloadsonly":   HomeScreenPreview(downloading: true, downloadsOnly: true)
        case "homepicks":           HomeScreenPreview(picks: true)
        case "homepicksdownloading": HomeScreenPreview(downloading: true, picks: true)
        case "homepicksonly":       HomeScreenPreview(picks: true, picksOnly: true)
        case "homepicksslow":       HomeScreenPreview(picks: true, slowDetails: true)
        case "homepicksfirstrun":   HomeScreenPreview(picks: true, picksOnly: true, firstRun: true)
        case "homepicksarrive":     HomeScreenPreview(picks: true, picksOnly: true, arrive: true)
        case "downloadstrip":       DownloadStripPreview()
        case "watchlist":           WatchlistScreenPreview()
        case "watchlistremove":     WatchlistScreenPreview(removeFocusedAfter: .seconds(20))
        case "homemenu":            MenuWrappedPreview { HomeScreenPreview() }
        case "browsemenu":          MenuWrappedPreview { BrowseScreenPreview() }
        case "watchlistmenu":       MenuWrappedPreview { WatchlistScreenPreview() }
        case "watchlistpartner":    WatchlistScreenPreview(partnerUnreadable: true)
        case "watchlistslow":       WatchlistScreenPreview(slowDetails: true)
        case "letterboxd":          LetterboxdCardPreview()
        case "letterboxdtoast":     LetterboxdToastPreview()
        case "letterboxdrating":    LetterboxdRatingPreview(existing: nil)
        case "letterboxdrerating":  LetterboxdRatingPreview(existing: 7)
        case "letterboxdinvite":    LetterboxdRatingPreview(existing: nil, invite: true)
        case "spin":                WatchlistSpinPreview()
        case "spinnoart":           WatchlistSpinPreview(withArt: false)
        case "serverprobe":         ServerReachabilityPreview()
        case "styles":              StyleGalleryPreview(initialFocus: .trailer)
        case "stylescard":          StyleGalleryPreview(initialFocus: .poster(1))
        case "stylesplain":         StyleGalleryPreview(initialFocus: .versions)
        case "plexrails":           PlexRailsPreview()
        case "plexrailsnoart":      PlexRailsPreview(variant: .noArt)
        case "plexrailsinsert":     PlexRailsPreview(variant: .insert)
        case "plexrailsinsertearly": PlexRailsPreview(variant: .insertEarly)
        case "browse":              BrowseScreenPreview()
        case "browseinsert":        BrowseScreenPreview(insertAbove: true)
        case "browsefailed":        BrowseScreenPreview(failing: true)
        case "browsetrendingfails": BrowseScreenPreview(trendingFails: true)
        case "library":             MyLibraryScreenPreview()
        case "librarydownloadends":   MyLibraryScreenPreview(downloadChange: .ends)
        case "librarydownloadstarts": MyLibraryScreenPreview(downloadChange: .starts)
        case "librarydownloadfocusedends": MyLibraryScreenPreview(downloadChange: .focusedEnds)
        case "search":              SearchScreenPreview()
        default:           ScrubBarPreview()
        }
    }
}

// MARK: - Version list

/// The real `VersionList` on fabricated streams, so the Instant / Download blocks, the "Larger
/// files" / "Recommended" split inside each, and both Hebrew marks can be screenshot-verified
/// without a session, a search round-trip, or the focus engine.
///
/// The fixture is deliberately the shape that prompted each change: oversized REMUXes the ranking
/// pushes to the bottom, and instant releases the ranking interleaves with downloads. It also
/// proves the grouping itself, since the blocks are computed by `groupedByAvailability` here
/// exactly as in the screen.
private struct VersionListPreview: View {
    private static func stream(_ name: String, _ gb: Double, _ res: String,
                               _ source: String, cached: Bool, subs: [String] = [],
                               languages: [String] = ["en"], video: String? = nil,
                               audio: String? = nil) -> CachedStream {
        CachedStream(infoHash: name, fileIdx: nil, rawTitle: name,
                     parsed: ParsedRelease(title: "Sherlock", year: 2010, resolution: res, source: source,
                                           videoCodec: video, audioCodec: audio),
                     languages: languages, sizeBytes: Int(gb * 1_000_000_000),
                     sourceName: "RD", isCached: cached, subtitleLanguages: subs)
    }

    private static let all: [CachedStream] = [
        stream("Sherlock.2160p.REMUX.HDR", 78, "2160p", "REMUX", cached: true),
        stream("Sherlock.2160p.REMUX.SDR", 64, "2160p", "REMUX", cached: false),
        stream("Sherlock.2160p.BluRay.x265", 41, "2160p", "BluRay", cached: true),
        stream("Sherlock.2160p.WEB-DL.x265", 22, "2160p", "WEB-DL", cached: true),
        stream("Sherlock.1080p.BluRay.x264", 12, "1080p", "BluRay", cached: true),
        stream("Sherlock.2160p.WEB-DL.DV.x265", 18, "2160p", "WEB-DL", cached: false),
        stream("Sherlock.1080p.WEB-DL.x265", 6, "1080p", "WEB-DL", cached: false),
        stream("Sherlock.720p.BluRay.x264.HebSubs", 3, "720p", "BluRay", cached: true, subs: ["he"]),
        // The shape that squeezed every chip mid-word on the real list: four languages, four
        // quality chips and the Matched pill on one row.
        stream("Sherlock.2010.Eng.Fre.Spa.Ita.1080p.BluRay.Remux.AVC.DTS-HD.MA-SGF", 30, "1080p", "REMUX",
               cached: true, languages: ["en", "fr", "es", "it"], video: "AVC", audio: "DTS-HD"),
    ]

    /// Two releases matched by a Hebrew subtitle (a download, and the crowded instant REMUX) and one
    /// tagged HebSubs (instant): the HebSubs one sits under the in-file mark, the others carry the pill.
    private static let evidence = SubtitleEvidenceSet.candidates(
        all, hebrewResults: [SubtitleResult(fileID: 1, language: "he", release: "Sherlock.1080p.WEB-DL.x265"),
                        SubtitleResult(fileID: 2, language: "he",
                                       release: "Sherlock.2010.Eng.Fre.Spa.Ita.1080p.BluRay.Remux.AVC.DTS-HD.MA-SGF")],
        originalLanguage: "en")

    var body: some View {
        let groups = Self.all.rankedFor(originalLanguage: "en", subtitles: Self.evidence)
            .groupedByAvailability(episodesInSeason: nil)
        ScrollView {
            VersionList(groups: groups, picking: nil, onPick: { _ in },
                        hebrew: { Self.evidence.hebrew(forVersion: $0.infoHash) })
                .padding(.horizontal, 60).padding(.vertical, 40)
                .frame(maxWidth: 1400, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

// MARK: - Person page

/// The real `PersonScreen` on a fake credits provider, so the header, the two role sections and
/// the grid's focus geometry can be screenshot-verified without a session or a network.
///
/// The fake deliberately includes a "Self" credit and a Producer credit — neither should appear,
/// which makes this a visual check on the DebridCore ranking as well as on the layout.
private struct PersonScreenPreview: View {
    private static let ref = TMDBPersonRef(id: 1234, name: "Denis Villeneuve")

    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))
    @State private var art = TitleArtStore(details: TMDBDetailsService(
        client: TMDBClient(apiKey: Secrets.tmdbAPIKey)))

    var body: some View {
        NavigationStack {
            PersonScreen(ref: Self.ref,
                         store: PersonStore(ref: Self.ref, credits: FakePersonCredits()),
                         art: art)
        }
        .environment(session)
        // `BrowseTile` reads this, and in the app the shell provides it above every pushed
        // destination. Without it here the harness traps on a missing Observable.
        .environment(session.makeTileWatchMarks())
    }
}

private struct FakePersonCredits: PersonCreditsProviding {
    func person(tmdbID: Int) async throws -> TMDBPersonDetails {
        // Real TMDB ids and posters, so the backdrop has art to follow. (A credit with no poster
        // is dropped by the filmography rules, so every shown one needs a poster.)
        func credit(_ id: Int, _ title: String, _ popularity: Double, poster: String? = nil,
                    character: String? = nil, job: String? = nil) -> TMDBPersonCredit {
            TMDBPersonCredit(
                result: TMDBSearchResult(id: id, title: title, name: nil,
                                         releaseDate: "2021-01-01", firstAirDate: nil,
                                         posterPath: poster, overview: nil, voteAverage: 7.5),
                kind: .movie, character: character, job: job, popularity: popularity)
        }
        return TMDBPersonDetails(
            id: tmdbID, name: "Denis Villeneuve", profilePath: nil,
            knownForDepartment: "Directing",
            castCredits: [credit(1, "Talk Show", 99, poster: "/p.jpg", character: "Self"),  // must NOT appear
                          credit(949, "Heat", 20, poster: "/umSVjVdbVwtx5ryCA2QXL44Durm.jpg",
                                 character: "Man in Bar"),
                          credit(670, "Oldboy", 10, poster: "/pWDtjs568ZfOTMbURQBYuT4Qxka.jpg",
                                 character: "Officer")],
            crewCredits: [credit(693134, "Dune: Part Two", 140, poster: "/6izwz7rsy95ARzTR3poZ8H6c5pp.jpg", job: "Director"),
                          credit(329865, "Arrival", 90, poster: "/pEzNVQfdzYDzVK0XqxERIw2x2se.jpg", job: "Director"),
                          credit(335984, "Blade Runner 2049", 80, poster: "/gajva2L0rPYkEWjzgFlBXCAVBE5.jpg", job: "Director"),
                          credit(273481, "Sicario", 70, poster: "/lz8vNyXeidqqOdJW9ZjnDAMb5Vr.jpg", job: "Director"),
                          credit(146233, "Prisoners", 65, poster: "/uhviyknTT5cEQXbn6vWIqfM4vGm.jpg", job: "Director"),
                          credit(181886, "Enemy", 40, poster: "/vf40tyDRKZsBmaLsYeopzfFLzLx.jpg", job: "Director"),
                          credit(46738, "Incendies", 35, poster: "/yH6DAQVgbyj72S66gN4WWVoTjuf.jpg", job: "Director"),
                          credit(8, "Produced Thing", 200, poster: "/p.jpg", job: "Producer")]) // must NOT appear
    }
}

// MARK: - Grid top fade

/// A pinned header over an already-scrolled grid — the shape every results grid in the app has, and
/// the shape whose top edge used to guillotine a poster in half.
///
/// The tiles are flat white on purpose. The fade is a brightness ramp, and a ramp is measurable on
/// a flat field and guesswork on a poster; the 100pt default was picked by sampling a column here.
/// They sit over a real ultrablur backdrop, as every grid page now does: the faded band must show
/// the art through it, never a navy bar.
/// Booting straight to it also takes the focus engine out of the question — reaching a real
/// scrolled grid means walking the nav rail with synthesized presses that land where they like.
private struct GridTopFadePreview: View {
    /// Dune: Part Two's backdrop — busy, bright art, the hardest case for a fade to read as soft.
    private static let backdrop = "/eZ239CUp1d6OryZEBPnO2n87gMG.jpg"

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(spacing: 24) {
                HStack(spacing: 16) {
                    Button("Movies") {}.buttonStyle(SeretPillStyle(selected: true))
                    Button("TV Shows") {}.buttonStyle(SeretPillStyle(selected: false))
                }
                .padding(.top, 30)
                .padding(.horizontal, PosterGridLayout.rootInset)
                .frame(maxWidth: .infinity, alignment: .leading)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: PosterGridLayout.columns, spacing: PosterGridLayout.rowSpacing) {
                            ForEach(0..<40, id: \.self) { i in
                                Color.white
                                    .frame(width: PosterTileMetrics.width, height: PosterTileMetrics.height)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.posterCorner,
                                                                style: .continuous))
                                    .id(i)
                            }
                        }
                        .padding(.horizontal, PosterGridLayout.rootInset)
                        .padding(.vertical, PosterGridLayout.topPadding)
                    }
                    .gridTopFade()
                    // Scrolled on arrival, so a row is genuinely crossing the top edge. Without it
                    // the fade band sits in the grid's padding and shows nothing at all.
                    .onAppear { proxy.scrollTo(20, anchor: .top) }
                }
            }
            .sideMenuContentInset()
            .background { FullBleedUltrablur(backdropPath: Self.backdrop, showsArt: false) }
        }
    }
}

// MARK: - OpenSubtitles pairing

/// The pairing card on its own, so the QR can be verified without a signed-in session.
///
/// This exists because the alternative did not work: reaching Settings in the simulator means
/// walking the focus engine down the nav rail, and synthesized key presses there land where they
/// like — several attempts ended up in the page instead of on the gear. The card needs no session,
/// so booting straight to it removes the navigation from the question entirely. It also exercises
/// the real `LocalPairingServer`, so a blank QR here means the listener or the address lookup
/// genuinely failed rather than the screenshot being mistimed.
private struct OpenSubtitlesPreview: View {
    @State private var model = SettingsModel(
        secretStore: KeychainSecretStore(service: "com.solomons.seret.opensubtitles.preview"))

    var body: some View {
        NavigationStack { OpenSubtitlesPage(model: model) }
    }
}

// MARK: - Side menu

/// Both menu states over a stand-in page, so the capsule/panel geometry and the label reveal can be
/// screenshot-verified without a signed-in session or the focus engine. `focusMenu` puts focus on
/// a row of the COLLAPSED capsule — the state tvOS can leave behind after a selection — to show its
/// white circle.
///
/// `live` (`-uiPreview sidemenulive`) instead drives the menu with `LibraryShell`'s own open/close
/// rules — `.onMoveCommand`, the focus-entry/exit handler, `pageHasHeldFocus`, Menu-to-open and
/// collapse-on-select — so the remote walkthrough can run without a signed-in session. Keep those
/// rules in step with the shell's.
private struct SideMenuPreview: View {
    var startExpanded = false
    var focusMenu = false
    var live = false

    @FocusState private var focus: SideMenuItem?
    @FocusState private var pageFocus: Int?
    @State private var selected: SideMenuItem = .home
    @State private var menuExpanded = false
    @State private var pageHasHeldFocus = false

    private var expanded: Bool { live ? menuExpanded : startExpanded }

    var body: some View {
        ZStack(alignment: .leading) {
            CanvasBackground()
            fakePage
                .sideMenuContentInset()
                .focusSection()
            SideMenuScrim(visible: expanded)
            SideMenu(selected: selected, profileName: "Shahar",
                     profileAvatar: "", profileColorTag: Theme.Palette.defaultColorTag,
                     focus: $focus,
                     expanded: expanded,
                     onSelect: { item in
                         guard item.isPage else { return }
                         selected = item
                         menuExpanded = false
                     },
                     onProfile: {})
            .onMoveCommand { _ in if live && focus != nil { menuExpanded = true } }
        }
        // Content claims initial focus so the menu starts CLOSED. `.defaultFocus` is the only one
        // of the three candidates that actually wins here — `prefersDefaultFocus(in:)` (leaf or
        // container) loses to tvOS's top-leading heuristic, which the menu always satisfies.
        .defaultFocus($pageFocus, 0)
        .onExitCommand(perform: !live || menuExpanded ? nil : {
            focus = selected
            menuExpanded = true
        })
        .onChange(of: focus) { _, new in
            guard live else { return }
            if new == nil {
                pageHasHeldFocus = true
                menuExpanded = false
            } else if pageHasHeldFocus {
                menuExpanded = true
            }
        }
        .onAppear {
            if !live { selected = .movies }
            if startExpanded || focusMenu { focus = .movies }
        }
        .task {
            guard live else { return }
            try? await Task.sleep(for: .milliseconds(800))
            if focus == nil { pageHasHeldFocus = true }
        }
    }

    /// Focusable stand-in posters, so initial focus has somewhere real to land. Live, two rails
    /// (so LEFT can be tried from different heights) titled with the selected page, so a selection
    /// shows on screen.
    private var fakePage: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text(live ? selected.title : "Trending Now").sectionTitle()
            ForEach(0..<(live ? 2 : 1), id: \.self) { rail in
                HStack(spacing: 36) {
                    ForEach(0..<6, id: \.self) { i in
                        Button {} label: {
                            RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous)
                                .fill(Theme.Palette.surface2)
                                .frame(width: 220, height: 330)
                        }
                        .buttonStyle(FocusCardStyle())
                        .focused($pageFocus, equals: rail * 10 + i)
                    }
                }
            }
        }
        .padding(Theme.Layout.contentMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Movie Detail

/// The real `MovieDetailView` on a stub store that reports a linked rating service, so the star row
/// renders (it's hidden without a watch store) alongside the Versions header. Sign-in free, which
/// is what makes the star styling and the focus geometry between them verifiable in the simulator.
/// An episode row for an episode you own THREE copies of.
///
/// Exists because the real account has no episode with duplicate copies, so the owned-copies
/// "Versions" menu — the half of the feature that only appears when there IS a choice — cannot be
/// reached with live data. The fixture also pins the ordering: the sources are handed over
/// worst-first, so a correctly-ranked row shows the right-sized 2160p first and the 40 GB REMUX
/// last.
/// The two things an empty episode row can say, each beside a skeleton card so a screenshot shows
/// they hold the row's height — the property that keeps the page from jumping when one replaces
/// the skeletons.
private struct EpisodeNoticePreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            HStack(alignment: .top, spacing: 30) {
                EpisodePlaceholderCard()
                EpisodeNoticeCard(message: "No episodes in this season yet.")
            }
            .border(.red.opacity(0.5))
            HStack(alignment: .top, spacing: 30) {
                EpisodePlaceholderCard()
                EpisodeNoticeCard(message: "Couldn\u{2019}t load this season\u{2019}s episodes.",
                                  retry: {})
            }
            .border(.red.opacity(0.5))
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CanvasBackground())
    }
}

private struct EpisodeVersionsPreview: View {
    @State private var store: DetailStore = {
        func src(_ id: String, _ res: String, _ source: String, _ gb: Double) -> MediaSource {
            MediaSource(torrentID: id, fileID: nil, restrictedLink: "rd://\(id)",
                        parsed: ParsedRelease(title: "Sherlock", season: 1, episode: 1,
                                              resolution: res, source: source),
                        sizeBytes: Int(gb * 1_000_000_000))
        }
        // Deliberately worst-first on input.
        let ranked = [src("remux", "2160p", "REMUX", 40),
                      src("web", "2160p", "WEB-DL", 5),
                      src("hd", "1080p", "WEB-DL", 2)].bestFirst()
        let ep = Episode(season: 1, number: 1, source: ranked[0],
                         alternates: Array(ranked.dropFirst()))
        let item = MediaItem(id: "s", kind: .show, title: "Sherlock", year: 2010,
                             sources: [], seasons: [Season(number: 1, episodes: [ep])],
                             tmdbID: 19885)
        return DetailStore(item: item, details: PreviewDetails(), watch: PreviewWatchRating())
    }()
    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))

    var body: some View {
        let rows = store.episodes(forSeason: 1)
        return NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("Owned copies, best-first — long-press the card for the menu")
                    .font(.seretCallout).foregroundStyle(Theme.Palette.textSecondary)
                // The ranked order, rendered as text so a screenshot proves it without needing the
                // context menu to be driven open.
                ForEach(rows.first?.ownedVersions ?? [], id: \.self) { s in
                    Text("\(s.parsed.resolution ?? "?") · \(s.parsed.source ?? "?") · "
                         + ByteCountFormatter.string(fromByteCount: Int64(s.sizeBytes ?? 0),
                                                     countStyle: .file))
                        .font(.seretTitle3)
                }
                Text("hasAlternateVersions: \(rows.first?.hasAlternateVersions == true ? "YES" : "NO")")
                    .font(.seretTitle3).foregroundStyle(Theme.Palette.textPrimary)
                if let row = rows.first {
                    EpisodeRow(store: store, row: row)
                }
            }
            .padding(60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(CanvasBackground())
        }
        .environment(session)
        .environment(session.makeTileWatchMarks())
    }
}

private struct MovieDetailPreview: View {
    /// Whether the fixture film starts on the watchlist, so both faces of the toggle can be
    /// screenshot-verified without a Letterboxd account or a server.
    var onWatchlist = false

    @State private var store: DetailStore = {
        let s = MediaSource(torrentID: "t", fileID: nil, restrictedLink: "rd://x",
                            parsed: ParsedRelease(title: "The Odyssey", year: 2026,
                                                  resolution: "1080p", source: "TELESYNC",
                                                  videoCodec: "x264"))
        let item = MediaItem(id: "m", kind: .movie, title: "The Odyssey", year: 2026,
                             sources: [s], seasons: [], tmdbID: 1_242_011,
                             overview: "Odysseus takes the long way home.")
        return DetailStore(item: item, details: PreviewDetails(), watch: PreviewWatchRating(),
                           ratings: PreviewRatings(), letterboxd: PreviewLetterboxdRating())
    }()
    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))

    @State private var watchlist: WatchlistMarks?

    var body: some View {
        NavigationStack { MovieDetailView(store: store) }
            .environment(session)
            // The similar/franchise rails render `BrowseTile`, which reads this.
            .environment(session.makeTileWatchMarks())
            // `DetailView` normally provides this; rendering `MovieDetailView` directly skips it,
            // and the Watchlist button is not offered without it.
            .environment(watchlist)
            // `DetailView` normally drives the rich load; rendering `MovieDetailView` directly
            // skips it, and without it there is no cast and no director to look at.
            .task { await store.load() }
            .task {
                let marks = PreviewWatchlist.marks(startingOn: onWatchlist, tmdbID: 1_242_011)
                await marks.load()
                watchlist = marks
            }
    }
}

// MARK: - Title pages with real art

/// Whiplash as an owned film, with everything the title page can show: real TMDB backdrop and
/// logo, a part-watched resume (so Resume and From Start both appear), two owned versions, the
/// public scores, a director, cast, a franchise rail and More Like This with real posters. The
/// composition check for the Plex-style page; `detail` stays the no-art case.
private struct MovieDetailArtPreview: View {
    nonisolated static let tmdbID = 244_786
    nonisolated static let item: MediaItem = {
        func src(_ id: String, _ res: String, _ source: String, _ gb: Double) -> MediaSource {
            MediaSource(torrentID: id, fileID: nil, restrictedLink: "rd://\(id)",
                        parsed: ParsedRelease(title: "Whiplash", year: 2014, resolution: res,
                                              source: source, videoCodec: "HEVC"),
                        sizeBytes: Int(gb * 1_000_000_000))
        }
        return MediaItem(id: "movie:tmdb:244786", kind: .movie, title: "Whiplash", year: 2014,
                         sources: [src("bd", "2160p", "BluRay", 18), src("web", "1080p", "WEB-DL", 4)],
                         seasons: [], tmdbID: tmdbID, posterPath: "/7fn624j5lj3xTme2SgiLCeuedmO.jpg",
                         backdropPath: nil,
                         overview: "Under the direction of a ruthless instructor, a talented young drummer begins to pursue perfection at any cost, even his humanity.")
    }()

    @State private var store = DetailStore(
        item: MovieDetailArtPreview.item, details: Details(),
        watch: PreviewWatchStates([WatchKey.content(forMovie: MovieDetailArtPreview.item): (2472, 6420, false)]),
        ratings: PreviewRatings(), letterboxd: PreviewLetterboxdRating())
    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))
    @State private var watchlist: WatchlistMarks?

    var body: some View {
        NavigationStack { MovieDetailView(store: store) }
            .environment(session)
            .environment(session.makeTileWatchMarks())
            .environment(watchlist)
            .task { await store.load() }
            .task {
                let marks = PreviewWatchlist.marks(startingOn: false, tmdbID: Self.tmdbID)
                await marks.load()
                watchlist = marks
            }
    }

    private struct Details: MediaDetailsProviding {
        func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
            try? await Task.sleep(for: .milliseconds(300))      // the page's settle, as on a network
            return TMDBMovieDetails(
                id: tmdbID, title: "Whiplash", releaseDate: "2014-10-10",
                overview: MovieDetailArtPreview.item.overview, posterPath: "/7fn624j5lj3xTme2SgiLCeuedmO.jpg",
                backdropPath: "/fRGxZuo7jJUWQsVg9PREb98Aclp.jpg", runtime: 107,
                genres: [TMDBGenre(id: 18, name: "Drama"), TMDBGenre(id: 10402, name: "Music")],
                voteAverage: 8.4, originalLanguage: "en", imdbID: "tt2582802",
                cast: [TMDBCastMember(id: 1, name: "Miles Teller", character: "Andrew Neiman", profilePath: nil),
                       TMDBCastMember(id: 2, name: "J.K. Simmons", character: "Terence Fletcher", profilePath: nil),
                       TMDBCastMember(id: 3, name: "Paul Reiser", character: "Jim Neiman", profilePath: nil),
                       TMDBCastMember(id: 4, name: "Melissa Benoist", character: "Nicole", profilePath: nil),
                       TMDBCastMember(id: 5, name: "Austin Stowell", character: nil, profilePath: nil)],
                directors: [TMDBPersonRef(id: 136495, name: "Damien Chazelle")],
                similar: PreviewArt.films,
                collection: TMDBCollectionRef(id: 9001, name: "Chazelle Collection"),
                images: TMDBImageSet(backdrops: [], logos: [
                    TMDBImageRef(filePath: "/kTmh3W4iWQnNUcnYNgxgOVhpzCe.png", languageCode: "en",
                                 voteAverage: 5, width: 500)]))
        }
        func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw CancellationError() }
        func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
        func collection(id: Int) async throws -> TMDBCollection? {
            TMDBCollection(id: id, name: "Chazelle Collection", parts: [
                TMDBSearchResult(id: MovieDetailArtPreview.tmdbID, title: "Whiplash", name: nil,
                                 releaseDate: "2014-10-10", firstAirDate: nil,
                                 posterPath: "/7fn624j5lj3xTme2SgiLCeuedmO.jpg", overview: nil, voteAverage: 8.4),
                TMDBSearchResult(id: 1_288_069, title: "Tenzing", name: nil, releaseDate: "2016-12-09",
                                 firstAirDate: nil, posterPath: "/eI0QW02PYqhnmIvLRdn9vrfVVP7.jpg",
                                 overview: nil, voteAverage: 7.9),
                TMDBSearchResult(id: 1_058_424, title: "Hope", name: nil, releaseDate: "2018-10-12",
                                 firstAirDate: nil, posterPath: "/6VY1ZKgpsc8CfGsQcCGiYEgHdH0.jpg",
                                 overview: nil, voteAverage: 7.1),
            ])
        }
    }
}

/// MobLand as an owned show: real backdrop, no logo (the title stands in), two seasons, season 1
/// fully owned with episode 1 watched and episode 2 part-watched, cast and More Like This. The
/// show page's composition check: action row, season pills, episode cards with ✓ and progress.
private struct ShowDetailArtPreview: View {
    nonisolated static let tmdbID = 247_718
    nonisolated static let item: MediaItem = {
        func ep(_ season: Int, _ n: Int) -> Episode {
            Episode(season: season, number: n,
                    source: MediaSource(torrentID: "t\(season)\(n)", fileID: nil, restrictedLink: "rd://\(n)",
                                        parsed: ParsedRelease(title: "MobLand", season: season, episode: n,
                                                              resolution: "2160p", source: "WEB-DL")))
        }
        return MediaItem(id: "show:tmdb:247718", kind: .show, title: "MobLand", year: 2025, sources: [],
                         seasons: [Season(number: 1, episodes: (1...6).map { ep(1, $0) }),
                                   Season(number: 2, episodes: [ep(2, 1)])],
                         tmdbID: tmdbID, posterPath: "/5Xc7WpWsgflfgEMoBlf9TmWhfbH.jpg",
                         backdropPath: "/h0OC7ouop8YLwbAVfS3UUE2Lw4T.jpg",
                         overview: "Two rival crime families collide in London, and the fixer caught between them has to keep both alive.")
    }()

    @State private var store = DetailStore(
        item: ShowDetailArtPreview.item, details: Details(),
        watch: PreviewWatchStates([
            WatchKey.content(forShow: ShowDetailArtPreview.item, season: 1, number: 1): (3100, 3100, true),
            WatchKey.content(forShow: ShowDetailArtPreview.item, season: 1, number: 2): (1300, 3000, false),
        ]),
        ratings: PreviewRatings())
    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))

    var body: some View {
        NavigationStack { ShowDetailView(store: store) }
            .environment(session)
            .environment(session.makeTileWatchMarks())
            .task { await store.load() }
    }

    nonisolated private static let stills = ["/h0OC7ouop8YLwbAVfS3UUE2Lw4T.jpg", "/mNHRGO1gFpR2CYZdANe72kcKq7G.jpg",
                                 "/hzznrBI07C2chXivlLYvEmQESP7.jpg", "/6gqezQJ2mkm4jreWwLyOZy2Vf6i.jpg",
                                 "/kVtOcoUJ68chBD2tmERkdWz7lK5.jpg", "/r08LxMJCbf1SiJIWeyH9aJmdqwC.jpg"]

    private struct Details: MediaDetailsProviding {
        func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw CancellationError() }
        func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
            try? await Task.sleep(for: .milliseconds(300))
            return TMDBTVDetails(
                id: tmdbID, name: "MobLand", firstAirDate: "2025-03-30",
                overview: ShowDetailArtPreview.item.overview, posterPath: "/5Xc7WpWsgflfgEMoBlf9TmWhfbH.jpg",
                backdropPath: "/h0OC7ouop8YLwbAVfS3UUE2Lw4T.jpg", numberOfSeasons: 2,
                genres: [TMDBGenre(id: 80, name: "Crime"), TMDBGenre(id: 18, name: "Drama")],
                voteAverage: 8.5, originalLanguage: "en", imdbID: "tt31510819",
                cast: [TMDBCastMember(id: 1, name: "Tom Hardy", character: "Harry Da Souza", profilePath: nil),
                       TMDBCastMember(id: 2, name: "Helen Mirren", character: "Maeve Harrigan", profilePath: nil),
                       TMDBCastMember(id: 3, name: "Pierce Brosnan", character: "Conrad Harrigan", profilePath: nil)],
                creatorRefs: [TMDBPersonRef(id: 9, name: "Ronan Bennett")],
                similar: PreviewArt.shows)
        }
        func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] {
            try? await Task.sleep(for: .milliseconds(400))
            return (1...6).map { n in
                TMDBEpisodeDetails(episodeNumber: n, name: ["Stick or Twist", "Rules of Engagement",
                                                            "Something Rotten", "Sweet Sorrow",
                                                            "Pick a Side", "Love & War"][n - 1],
                                   overview: "Harry is pulled deeper into the Harrigans' war as old debts come due.",
                                   stillPath: ShowDetailArtPreview.stills[n - 1], runtime: 52,
                                   airDate: "2025-04-\(String(format: "%02d", n))")
            }
        }
    }
}

/// Real TMDB posters for the title pages' More Like This rails.
private enum PreviewArt {
    static let films: [TMDBSearchResult] = [
        ("Tenzing", 1_288_069, "/eI0QW02PYqhnmIvLRdn9vrfVVP7.jpg"),
        ("Hope", 1_058_424, "/6VY1ZKgpsc8CfGsQcCGiYEgHdH0.jpg"),
        ("Masterplan", 1_561_726, "/5xmXVd7nCK3tAo34XkO58SxUCip.jpg"),
        ("Spider-Man: Brand New Day", 969_681, "/bjiS5ipwxb9JFy3XRRN4OAilSeX.jpg"),
        ("Clayface", 1_400_940, "/5jCpQnWPikggmQZoDp1eAi6BI6w.jpg"),
    ].map { TMDBSearchResult(id: $0.1, title: $0.0, name: nil, releaseDate: "2026-01-01",
                             firstAirDate: nil, posterPath: $0.2, overview: nil, voteAverage: 7) }
    static let shows: [TMDBSearchResult] = [
        ("Tulsa King", 153_312, "/rOYLWCdAifpUtPlTf1WHxyaxeMt.jpg"),
        ("The Diplomat", 203_857, "/cUy0ZYme43lop08nOtbQLWL0dX.jpg"),
        ("Lanterns", 95_350, "/rb94rKVIzLyfWufIN7WqLvadBDH.jpg"),
    ].map { TMDBSearchResult(id: $0.1, title: nil, name: $0.0, releaseDate: nil,
                             firstAirDate: "2024-01-01", posterPath: $0.2, overview: nil, voteAverage: 7) }
}

/// A watch store holding fixed states — `(position, duration, finished)` per content key — that
/// also rates, so the title pages show resume, ✓ and progress, and the stars.
private struct PreviewWatchStates: WatchProgressProviding, WatchRatingProviding {
    let states: [String: (Double, Double, Bool)]
    init(_ states: [String: (Double, Double, Bool)]) { self.states = states }

    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? {
        guard let (position, duration, finished) = states[key] else { return nil }
        return WatchState(contentKey: key, sourceKey: "", positionSeconds: position,
                          durationSeconds: duration, finished: finished, updatedAt: Date())
    }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws {}
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
    func deleteProgress(forContentKeys keys: [String]) async throws {}
    func rating(forContentKey key: String) async -> Int? { nil }
    func setRating(_ value: Int?, forContentKey key: String) async {}
}

// MARK: - A show that has not premiered

/// The real `DetailView` for a show you do not own whose every listed episode airs in 2099.
private struct UnpremieredShowPreview: View {
    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))
    private static let show = MediaItem(id: "show:tmdb:999001", kind: .show, title: "The Long Way Home",
                                        year: 2099, sources: [], seasons: [], tmdbID: 999_001,
                                        overview: "A family saga that has not aired yet.")

    var body: some View {
        NavigationStack {
            DetailView(item: Self.show, details: Details(), watch: PreviewWatchRating())
        }
        .environment(session)
        .environment(session.makeTileWatchMarks())
    }

    private struct Details: MediaDetailsProviding {
        func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw CancellationError() }
        func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
            TMDBTVDetails(id: tmdbID, name: "The Long Way Home", firstAirDate: "2099-03-12",
                          overview: "A family saga that has not aired yet.", posterPath: nil,
                          backdropPath: nil, numberOfSeasons: 1, genres: [], voteAverage: nil)
        }
        func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] {
            (1...6).map { n in
                TMDBEpisodeDetails(episodeNumber: n, name: "Episode \(n)", overview: nil, stillPath: nil,
                                   runtime: 50, airDate: String(format: "2099-03-%02d", 11 + n))
            }
        }
    }
}

// MARK: - A download finishing on an open page

/// The real `DetailView` on a film you do not own, with a download of it under way that Real-Debrid
/// finishes `readyAfter` seconds in. The real `DownloadStore` and `LibraryStore` run on fakes: the
/// poll reports the torrent done, the library's next listing carries it, the READY badge is let go
/// and the page adopts the film — the whole path a real download takes, minus the account.
private struct DownloadFinishPreview: View {
    nonisolated static let tmdbID = 1_242_011
    nonisolated static let torrentID = "T-preview"
    static let readyAfter: TimeInterval = 25

    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))
    @State private var ready = false

    private static let placeholder = MediaItem(id: "movie:tmdb:1242011", kind: .movie,
                                               title: "The Odyssey", year: 2026, sources: [],
                                               seasons: [], tmdbID: tmdbID,
                                               overview: "Odysseus takes the long way home.")
    private static let owned = MediaItem(
        id: "movie:tmdb:1242011", kind: .movie, title: "The Odyssey", year: 2026,
        sources: [MediaSource(torrentID: torrentID, fileID: 1, restrictedLink: "rd://preview",
                              parsed: ParsedRelease(title: "The Odyssey", year: 2026,
                                                    resolution: "2160p"))],
        seasons: [], tmdbID: tmdbID, overview: "Odysseus takes the long way home.")

    var body: some View {
        NavigationStack {
            if ready {
                DetailView(item: Self.placeholder, details: PreviewDetails(), watch: PreviewWatchRating())
            } else {
                Color.black
            }
        }
        .environment(session)
        .environment(session.makeTileWatchMarks())
        .task { await setUp() }
    }

    private func setUp() async {
        let listing = Listing()
        let library = LibraryStore(library: listing)
        let downloads = DownloadStore(
            service: Service(), records: Records(),
            poller: Poller(readyAt: Date().addingTimeInterval(Self.readyAfter), listing: listing,
                           owned: Self.owned),
            deleter: Deleter(),
            onReady: { _ in library.reload() },          // as `AppSession` wires it
            pollInterval: .seconds(1))
        session.installStoresForPreview(library: library, downloads: downloads)
        await library.load()
        await downloads.request(contentKey: DownloadKey.movie(tmdbID: Self.tmdbID), tmdbID: Self.tmdbID,
                                title: "The Odyssey", kind: .movie,
                                candidates: [CachedStream(infoHash: "preview", fileIdx: nil,
                                                          rawTitle: "The.Odyssey.2026.2160p",
                                                          parsed: ParsedRelease(title: "The Odyssey",
                                                                                resolution: "2160p"),
                                                          languages: ["en"], sizeBytes: 40_000_000_000,
                                                          sourceName: nil)])
        ready = true
    }

    /// The account's torrent list: empty until the poll has reported the download done.
    private final class Listing: LibraryProviding, @unchecked Sendable {
        private let lock = NSLock()
        private var items: [MediaItem] = []
        func set(_ new: [MediaItem]) { lock.withLock { items = new } }
        func loadCached() -> [MediaItem]? { nil }
        func refresh() async throws -> [MediaItem] { lock.withLock { items } }
        func remove(_ item: MediaItem) async throws {}
        func removeVersion(_ item: MediaItem, source: MediaSource) async throws {}
    }

    private struct Service: DownloadRequesting {
        func startDownload(infoHash: String) async throws -> TorrentInfo {
            TorrentInfo(id: DownloadFinishPreview.torrentID, filename: "The.Odyssey.2026.2160p.mkv",
                        hash: infoHash, bytes: 40_000_000_000, progress: 40, status: "downloading",
                        files: [TorrentFile(id: 1, path: "/The.Odyssey.2026.2160p.mkv",
                                            bytes: 40_000_000_000, selected: 1)],
                        links: [])
        }
    }

    private final class Records: DownloadRecording, @unchecked Sendable {
        private let lock = NSLock()
        private var rows: [DownloadRequestData] = []
        func upsert(_ data: DownloadRequestData) async throws { lock.withLock { rows.append(data) } }
        func all() async throws -> [DownloadRequestData] { lock.withLock { rows } }
        func delete(torrentID: String) async throws { lock.withLock { rows.removeAll { $0.torrentID == torrentID } } }
    }

    private struct Deleter: DownloadDeleting {
        func deleteTorrent(id: String) async throws {}
    }

    /// Downloading at 40% until `readyAt`; then done — and from then on the account lists it.
    private struct Poller: DownloadPolling {
        let readyAt: Date
        let listing: Listing
        let owned: MediaItem
        func poll() async throws -> [DownloadStatus] {
            let key = DownloadKey.movie(tmdbID: DownloadFinishPreview.tmdbID)
            guard Date() >= readyAt else {
                return [DownloadStatus(torrentID: DownloadFinishPreview.torrentID, contentKey: key,
                                       tmdbID: DownloadFinishPreview.tmdbID, phase: .downloading,
                                       fraction: 0.4, title: "The Odyssey")]
            }
            listing.set([owned])
            return [DownloadStatus(torrentID: DownloadFinishPreview.torrentID, contentKey: key,
                                   tmdbID: DownloadFinishPreview.tmdbID, phase: .ready, fraction: 1,
                                   title: "The Odyssey")]
        }
    }
}

/// A `WatchlistMarks` over an in-memory mirror. No disk, no server — the button's two faces and
/// the confirmation are all it exists to show.
private enum PreviewWatchlist {
    @MainActor static func marks(startingOn: Bool, tmdbID: Int) -> WatchlistMarks {
        let mirror = Mirror(entries: startingOn
            ? [WatchlistEntry.locallyAdded(tmdbID: tmdbID, title: "The Odyssey", year: 2026,
                                           posterPath: nil, position: -1)]
            : [])
        return WatchlistMarks(entries: { await mirror.all },
                              add: { await mirror.add($0) },
                              remove: { await mirror.remove($0) },
                              relay: { .init(pushed: 1, failed: 0) })
    }

    private actor Mirror {
        var all: [WatchlistEntry]
        init(entries: [WatchlistEntry]) { all = entries }

        func add(_ film: WatchlistFilm) -> [WatchlistEntry] {
            var entry = WatchlistEntry.locallyAdded(tmdbID: film.tmdbID, title: film.title,
                                                    year: film.year, posterPath: film.posterPath,
                                                    position: -1)
            entry.addPushedAt = Date()
            all.append(entry)
            return all
        }

        func remove(_ slug: String) -> [WatchlistEntry] {
            all.removeAll { $0.slug == slug }
            return all
        }
    }
}

/// Inert details provider — the harness renders from the cached `MediaItem` alone.
/// Fixed scores, so the four-chip ratings row can be screenshot-verified without a network, an
/// OMDb key, or a Letterboxd round-trip. The Letterboxd figure is a real one: it has to read
/// correctly as "out of five" sitting beside IMDb's "out of ten".
private struct PreviewRatings: RatingsProviding {
    func ratings(imdbID: String) async throws -> OMDbRatings {
        OMDbRatings(imdb: 8.1, rottenTomatoes: 92, metacritic: 78)
    }
}

private struct PreviewLetterboxdRating: LetterboxdRatingProviding {
    func rating(forTMDB id: Int) async throws -> LetterboxdFilmRating? {
        LetterboxdFilmRating(score: 4.38, count: 3_654_485)
    }
}

private struct PreviewDetails: MediaDetailsProviding {
    /// Carries cast and a director so the harness can check the two controls that used to be inert
    /// text: the focusable cast rail, and the pressable director pill.
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
        TMDBMovieDetails(
            id: tmdbID, title: "The Odyssey", releaseDate: "2026-07-17", overview: nil,
            posterPath: nil, backdropPath: nil, runtime: 168, genres: [], voteAverage: 7.4,
            imdbID: "tt9218128",
            cast: [TMDBCastMember(id: 1, name: "Matt Damon", character: "Odysseus",
                                  profilePath: nil, order: 0),
                   TMDBCastMember(id: 2, name: "Tom Holland", character: "Telemachus",
                                  profilePath: nil, order: 1),
                   TMDBCastMember(id: 3, name: "Zendaya", character: "Melantho",
                                  profilePath: nil, order: 2),
                   TMDBCastMember(id: 4, name: "Anne Hathaway", character: "Penelope",
                                  profilePath: nil, order: 3)],
            directors: [TMDBPersonRef(id: 525, name: "Christopher Nolan")])
    }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw CancellationError() }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
}

/// A watch store that also rates — `DetailStore.canRate` keys off exactly this conformance.
private struct PreviewWatchRating: WatchProgressProviding, WatchRatingProviding {
    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { nil }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws {}
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
    func deleteProgress(forContentKeys keys: [String]) async throws {}
    func rating(forContentKey key: String) async -> Int? { nil }
    func setRating(_ value: Int?, forContentKey key: String) async {}
}

// MARK: - Scrub bar

/// Boots straight to `ScrubBar` in each of its states so its layout can be screenshot-verified.
private struct ScrubBarPreview: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 70) {
                labelled("Playing — 8pt bar, play glyph (the state)") { m in }
                labelled("Buffering — spinner in the glyph slot") { m in m.driveBuffering() }
                labelled("Paused — 10pt bar, larger knob, pause glyph") { m in m.drivePaused() }
                labelled("Scrubbing — target time over the knob, tick at the live playhead") { m in
                    m.driveScrubbing()
                }
                labelled("Skipping — the badge rides the knob and counts up") { m in
                    m.driveSkipping()
                }
            }
            .padding(.horizontal, 90)
        }
    }

    private func labelled(_ title: String,
                          drive: @escaping (PreviewDriver) -> Void) -> some View {
        PreviewBarRow(title: title, drive: drive)
    }
}

/// One driven bar plus its caption.
private struct PreviewBarRow: View {
    let title: String
    let drive: (PreviewDriver) -> Void
    @State private var driver = PreviewDriver()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.seretCallout).foregroundStyle(Theme.Palette.textSecondary)
            ScrubBar(model: driver.model, buffering: driver.buffering)
        }
        .task { await driver.prime(); drive(driver) }
    }
}

/// Builds a `PlayerModel` on a stub engine and drives it into a target state for the harness.
@MainActor
@Observable
final class PreviewDriver {
    let engine = PreviewEngine()
    let model: PlayerModel
    private(set) var buffering = false

    init() {
        let source = MediaSource(torrentID: "t", fileID: nil, restrictedLink: "rd://x",
                                 parsed: ParsedRelease(title: "Dune Part Two"))
        let item = MediaItem(id: "m", kind: .movie, title: "Dune: Part Two", year: 2024,
                             sources: [source], seasons: [], tmdbID: 693134)
        let request = PlaybackRequest(item: item, source: source, resumeAt: nil,
                                      label: "Dune: Part Two", contentKey: "m")
        model = PlayerModel(request: request, engine: engine,
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _, _ in }, subtitles: nil)
    }

    /// Bring the model to a live, rendered, playing state at ~41 minutes of a 2h9m film.
    func prime() async {
        model.start()
        try? await Task.sleep(for: .milliseconds(50))
        engine.emit(.time(.init(position: 2480, duration: 7784)))
        engine.emit(.time(.init(position: 2481, duration: 7784)))
        try? await Task.sleep(for: .milliseconds(50))
    }

    func driveBuffering() { buffering = true }

    func drivePaused() {
        engine.emit(.state(.paused))
    }

    func driveScrubbing() {
        model.beginScrub()
        model.updateScrub(by: 1600)   // glide the target well ahead of the playhead
    }

    /// Keep ±10s skips landing so the badge stays up and counts (+10s, +20s … +1:10 …). Each skip
    /// is followed by the tick a real engine sends from the new place.
    func driveSkipping() {
        Task { await PreviewSkipLoop.run(model: model, engine: engine) }
    }
}

/// Lands a forward skip every 0.45s — inside the badge's 0.8s burst window, so it accumulates —
/// followed by the engine's tick from the new position.
@MainActor
enum PreviewSkipLoop {
    static func run(model: PlayerModel, engine: PreviewEngine) async {
        while !Task.isCancelled {
            model.skip(10)
            try? await Task.sleep(for: .milliseconds(150))
            engine.emit(.time(.init(position: model.position + 0.2, duration: model.duration)))
            try? await Task.sleep(for: .milliseconds(300))
        }
    }
}

// MARK: - Input probe

/// Mounts a bare `PlayerInputSurface` over black with the probe HUD on top — no sign-in, no stream,
/// no library. That matters: it makes the remote-input question answerable on a signed-out device
/// or a fresh simulator, and it isolates the surface from every other thing that could swallow
/// input. Launch with `-uiPreview inputprobe -inputHUD`.
private struct InputProbePreview: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerInputSurface(
                isActive: true,
                onTouchDown: {}, onTouchUp: {},
                onScrubBegan: {}, onScrubMoved: { _ in },
                onScrubEnded: {}, onScrubCancelled: {},
                onSkip: { _ in }, onSelect: {}, onPlayPause: {}, onUp: {}, onDown: {},
                onScanBegan: { _ in }, onScanEnded: {}
            )
            .ignoresSafeArea()
            InputProbeHUD()
        }
    }
}

// MARK: - Subtitle panel + browser

/// The playback settings panel with muxed tracks grouped apart from downloaded ones.
private struct SettingsPanelPreview: View {
    @State private var driver = SubtitlePreviewDriver()
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RemoteImage(url: PlayerChromePreview.frame, contentMode: .fill) { _ in Color.black }
                .ignoresSafeArea()
            SettingsPanel(model: driver.model, initialSection: .subtitles,
                          onSearchSubtitles: {}, onSyncToLine: {}, onClose: {})
        }
        .task { await driver.primeWithTracks() }
    }
}

/// The full subtitle browser with ranked, badged Hebrew results (an exact hash match sorts first).
///
/// `failing: true` is the state the Apple TV was actually in: results listed, and a pick that
/// cannot be honoured. It exists because the browser used to close itself on failure, so the one
/// screen a viewer sees when the download is refused had never been looked at.
private struct SubtitleBrowserPreview: View {
    private let failing: Bool
    @State private var driver: SubtitlePreviewDriver

    init(failing: Bool = false) {
        self.failing = failing
        _driver = State(initialValue: SubtitlePreviewDriver(failing: failing))
    }

    var body: some View {
        SubtitleBrowser(model: driver.model, onClose: {})
            .task {
                await driver.primeAndSearch()
                if failing, let first = driver.model.subtitleSearchResults.first {
                    await driver.model.useSubtitle(first)
                }
            }
    }
}

/// The auto-sync bar over a stand-in film frame, in whichever of its three states.
///
/// A sync runs for minutes with the film still playing, so this bar is the only thing telling the
/// viewer it is alive — which makes its legibility over a bright picture the whole point, and that
/// is a thing only a screenshot can settle.
private struct AutoSyncBarPreview: View {
    let mood: PlayerModel.AutoSyncBanner.Mood

    var body: some View {
        ZStack {
            // A bright, busy stand-in for the picture: a dark bar on black proves nothing.
            LinearGradient(colors: [.orange, .white, .teal, .black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            AutoSyncBar(banner: banner)
        }
    }

    private var banner: PlayerModel.AutoSyncBanner {
        switch mood {
        case .measuring:
            .init(text: "Syncing subtitles  ·  about 3 min left", mood: .measuring, fraction: 0.38)
        case .synced:
            .init(text: "Subtitles synced  ·  shifted +1.4s", mood: .synced, fraction: nil)
        case .failed:
            .init(text: "Couldn't sync the subtitles \u{2014} nudge the timing by hand",
                  mood: .failed, fraction: nil)
        }
    }
}

/// Drives a `PlayerModel` wired to a canned subtitle provider for the panel/browser harnesses.
@MainActor
@Observable
final class SubtitlePreviewDriver {
    let engine = PreviewEngine()
    let model: PlayerModel

    init(failing: Bool = false, show: Bool = false, failingOpen: Bool = false) {
        let source = MediaSource(torrentID: "t", fileID: nil, restrictedLink: "rd://x",
                                 parsed: ParsedRelease(title: "Dune Part Two", year: 2024,
                                                       resolution: "2160p", source: "WEB-DL",
                                                       videoCodec: "H265", releaseGroup: "FLUX"))
        let request: PlaybackRequest
        if show {
            // An episode with its season alongside, so the strip (and the row's Episodes button)
            // has something to show. No TMDB here, so the episodes carry no names: the top line
            // falls back to "Episode 3".
            let episodes = (1...6).map { Episode(season: 1, number: $0, source: source) }
            let item = MediaItem(id: "s", kind: .show, title: "The Diplomat", year: 2023,
                                 sources: [], seasons: [Season(number: 1, episodes: episodes)],
                                 tmdbID: 203857)
            request = PlaybackRequest(item: item, source: source, resumeAt: nil,
                                      label: "The Diplomat — S1·E3", contentKey: "s:1x3",
                                      episode: episodes[2])
        } else {
            let item = MediaItem(id: "m", kind: .movie, title: "Dune: Part Two", year: 2024,
                                 sources: [source], seasons: [], tmdbID: 693134)
            request = PlaybackRequest(item: item, source: source, resumeAt: nil,
                                      label: "Dune: Part Two", contentKey: "m")
        }
        model = PlayerModel(request: request, engine: engine,
                            unrestrict: { _ in
                                if failingOpen { throw URLError(.badServerResponse) }
                                return URL(string: "https://cdn/x.mkv")!
                            },
                            recordProgress: { _, _, _, _, _ in },
                            subtitles: PreviewSubtitleProvider(failDownload: failing))
    }

    /// Play, then run a Hebrew search so the browser shows ranked rows.
    func primeAndSearch() async {
        model.start()
        try? await Task.sleep(for: .milliseconds(50))
        engine.emit(.time(.init(position: 2480, duration: 7784)))
        try? await Task.sleep(for: .milliseconds(30))
        await model.searchSubtitles(language: "he")
    }

    /// Play, then ask for Hebrew exactly as the viewer does, so the panel shows both groups AND
    /// the whole download → attach → select path that the picker's state depends on.
    ///
    /// The embedded Hebrew is a `bdpg` bitmap on purpose: that is the shape of the release the
    /// report came from, and it is the track the language preference used to take the selection
    /// back to the instant the download landed.
    func primeWithTracks() async {
        model.start()
        try? await Task.sleep(for: .milliseconds(50))
        engine.emit(.time(.init(position: 2480, duration: 7784)))
        engine.audioTracks = [
            MediaTrack(id: "es/1", kind: .audio, name: "English 5.1 [English]", language: "en", codec: "eac3"),
            MediaTrack(id: "es/2", kind: .audio, name: "Commentary [English]", language: "en", codec: "aac"),
            MediaTrack(id: "es/3", kind: .audio, name: "Français [French]", language: "fr", codec: "ac3"),
        ]
        engine.subtitleTracks = [
            MediaTrack(id: "spu/0", kind: .subtitle, name: "English SDH", language: "en", codec: "subt"),
            MediaTrack(id: "spu/1", kind: .subtitle, name: "Français", language: "fr", codec: "subt"),
            MediaTrack(id: "spu/2", kind: .subtitle, name: "עברית", language: "he", codec: "bdpg"),
        ]
        engine.emit(.tracksChanged)
        try? await Task.sleep(for: .milliseconds(30))
        await model.requestSubtitle(language: "he")
        try? await Task.sleep(for: .milliseconds(30))
    }
}

/// A subtitle provider that returns a fixed, ranking-friendly Hebrew set for the harness — one exact
/// file-hash match (perfect), one same-resolution BluRay (uncertain source), one poor CAM rip.
struct PreviewSubtitleProvider: SubtitleProvider {
    /// Refuse the download the way an unconfigured OpenSubtitles account does.
    var failDownload = false
    func search(_ query: SubtitleQuery, languages: [String]) async throws -> [SubtitleResult] {
        [
            SubtitleResult(fileID: 1, language: "he",
                           release: "Dune.Part.Two.2024.2160p.WEB-DL.H265-FLUX",
                           downloadCount: 240, fps: 23.976, moviehashMatch: true, uploader: "syncer"),
            SubtitleResult(fileID: 2, language: "he",
                           release: "Dune.Part.Two.2024.1080p.BluRay.x264-SPARKS",
                           downloadCount: 91_500, fps: 25.0, hearingImpaired: true, uploader: "subber"),
            SubtitleResult(fileID: 3, language: "he",
                           release: "Dune2.CAM.HEBSUB", downloadCount: 4_200, uploader: "anon"),
        ]
    }
    func download(_ result: SubtitleResult) async throws -> URL {
        if failDownload { throw SubtitleError.notAuthenticated }
        // A REAL file with real cues: a path with nothing behind it parses to no lines, which is
        // indistinguishable from a muxed track — and would hide every row gated on having cues.
        let url = FileManager.default.temporaryDirectory.appending(path: "preview-he.srt")
        try? Data("""
        1
        00:02:20,000 --> 00:02:23,000
        אני לא יודע מה לומר.

        2
        00:02:25,000 --> 00:02:28,000
        אז אל תגיד כלום.

        """.utf8).write(to: url)
        return url
    }
}

// MARK: - Player chrome

/// The REAL `PlayerView` — input surface, overlay routing, focus and all — on a stub engine over a
/// still, opened on the overlay under test. Nothing is re-composed for the harness, so what the
/// screenshot shows is what the player draws.
private struct PlayerChromePreview: View {
    let overlay: PlayerView.PreviewOverlay
    let paused: Bool
    let skipping: Bool
    let show: Bool
    let nearEnd: Bool
    /// After Up Next rises, the engine reports a stall (`.buffering`).
    let bufferingAtEnd: Bool
    let stage: Stage
    @State private var driver: SubtitlePreviewDriver

    /// How far the harness takes playback: to frames (the default), never past the cold open, or
    /// into a failed open.
    enum Stage { case playing, loading, failed }
    /// The player mounts once the model holds its tracks — as it does by the time a real viewer
    /// can reach the row — so the sheet seeds focus on the subtitle that is actually on.
    @State private var primed = false

    /// A bright, detailed frame, so legibility over a real picture is what gets judged.
    static let frame = TMDBClient.imageURL(path: "/fRGxZuo7jJUWQsVg9PREb98Aclp.jpg", size: "original")

    init(overlay: PlayerView.PreviewOverlay, paused: Bool = false, skipping: Bool = false,
         show: Bool = false, nearEnd: Bool = false, bufferingAtEnd: Bool = false,
         stage: Stage = .playing) {
        self.overlay = overlay
        self.nearEnd = nearEnd
        self.bufferingAtEnd = bufferingAtEnd
        self.paused = paused
        self.skipping = skipping
        self.show = show
        self.stage = stage
        _driver = State(initialValue: SubtitlePreviewDriver(show: show,
                                                            failingOpen: stage == .failed))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if primed {
                PlayerView(previewModel: driver.model, frame: Self.frame, opening: overlay)
            }
        }
        .task {
            guard stage == .playing else { primed = true; return }
            await driver.primeWithTracks()
            // Frames are moving: the cold-open overlay comes down.
            driver.engine.emit(.time(.init(position: 2481, duration: 7784)))
            driver.engine.emit(.state(.playing))
            try? await Task.sleep(for: .milliseconds(50))
            if show { await driver.model.loadSeasonEpisodes() }
            if paused { driver.engine.emit(.state(.paused)) }
            try? await Task.sleep(for: .milliseconds(50))
            primed = true
            if nearEnd {
                // Two ticks in the last stretch: playback is advancing there, so Up Next rises.
                try? await Task.sleep(for: .milliseconds(300))
                driver.engine.emit(.time(.init(position: 7760, duration: 7784)))
                try? await Task.sleep(for: .milliseconds(100))
                driver.engine.emit(.time(.init(position: 7761, duration: 7784)))
                if bufferingAtEnd {
                    try? await Task.sleep(for: .milliseconds(1200))
                    driver.engine.emit(.state(.buffering))
                }
            }
            if skipping {
                try? await Task.sleep(for: .milliseconds(600))
                await PreviewSkipLoop.run(model: driver.model, engine: driver.engine)
            }
        }
    }
}

// MARK: - Stub engine

/// A no-op engine that just relays emitted events — enough to drive the read-only overlay state.
@MainActor
final class PreviewEngine: VideoPlayerEngine {
    var audioTracks: [MediaTrack] = []
    var subtitleTracks: [MediaTrack] = []
    let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation

    init() {
        var c: AsyncStream<PlaybackEvent>.Continuation!
        events = AsyncStream { c = $0 }
        continuation = c
    }
    func emit(_ event: PlaybackEvent) { continuation.yield(event) }

    func load(url: URL, headers: [String: String], audioLanguage: String?,
              audioTrackID: String?) {}
    func play() {}
    func pause() {}
    func stop() { continuation.finish() }
    func seek(to seconds: Double) {}
    func setRate(_ rate: Double) {}
    func selectAudioTrack(id: String?) {}
    func selectSubtitleTrack(id: String?) {}

    /// Surface a slave the way VLCKit does — and only the way VLCKit does.
    ///
    /// It used to do nothing, and the panel harness hand-placed a track called "Hebrew" tagged
    /// `language: "he"` instead. VLCKit gives a slave NEITHER: it arrives named "Track 3" with no
    /// language at all, which is precisely why the picker printed "Track 3" for the Hebrew the
    /// viewer had just asked for, and why the language preference could not see it and took the
    /// selection back. A flattering fixture is a harness that cannot show you the bug.
    func addExternalSubtitle(url: URL) {
        guard !attachedSubtitleURLs.contains(url) else { return }   // libvlc keys a slave by URL
        attachedSubtitleURLs.append(url)
        subtitleTracks.append(MediaTrack(id: "ext/\(attachedSubtitleURLs.count)", kind: .subtitle,
                                         name: "Track \(subtitleTracks.count + 1)",
                                         language: nil, isExternal: true, codec: "subt"))
        emit(.tracksChanged)
    }
    private var attachedSubtitleURLs: [URL] = []
}

// MARK: - Manual sync panel

/// The real `ManualSyncPanel` over black, driven through the REAL path — a download that attaches,
/// is parsed for its cues, and is then pressed against. Nothing about the session is hand-placed,
/// so the harness cannot flatter a model that does not actually work.
///
/// The fixture is Hebrew on purpose: this is the first place in the app that renders subtitle text
/// itself, and right-to-left layout is worth looking at rather than assuming.
private struct ManualSyncPanelPreview: View {
    let pressed: Bool
    @State private var engine = PreviewEngine()
    @State private var model: PlayerModel

    init(pressed: Bool) {
        self.pressed = pressed
        let engine = PreviewEngine()
        let source = MediaSource(torrentID: "t", fileID: nil, restrictedLink: "rd://x",
                                 parsed: ParsedRelease(title: "Dune Part Two"))
        let item = MediaItem(id: "m", kind: .movie, title: "Dune: Part Two", year: 2024,
                             sources: [source], seasons: [], tmdbID: 693134)
        let request = PlaybackRequest(item: item, source: source, resumeAt: nil,
                                      label: "Dune: Part Two", contentKey: "m")
        _engine = State(initialValue: engine)
        _model = State(initialValue: PlayerModel(
            request: request, engine: engine,
            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
            recordProgress: { _, _, _, _, _ in }, subtitles: ManualSyncPreviewProvider()))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ManualSyncPanel(model: model, onClose: {})
        }
        .task {
            model.start()
            try? await Task.sleep(for: .milliseconds(50))
            // 2:34.4 into the film — inside the cue authored at 2:32, so that line is pre-selected
            // and a press measures +2.4s.
            engine.emit(.time(.init(position: 154.4, duration: 7784)))
            try? await Task.sleep(for: .milliseconds(30))
            await model.requestSubtitle(language: "he")
            try? await Task.sleep(for: .milliseconds(60))
            model.beginManualSync()
            if pressed { model.markSyncMoment() }
        }
    }
}

/// Serves one real Hebrew subtitle file, so the preview exercises the parse rather than a fixture
/// of pre-made cues.
private struct ManualSyncPreviewProvider: SubtitleProvider {
    func search(_ query: SubtitleQuery, languages: [String]) async throws -> [SubtitleResult] {
        [SubtitleResult(fileID: 7, language: "he", release: "Dune.Part.Two.2024.2160p.WEB-DL",
                        downloadCount: 400, fps: 23.976, moviehashMatch: true, uploader: "syncer")]
    }
    func download(_ result: SubtitleResult) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "preview-manual-sync.srt")
        try? Data(Self.srt.utf8).write(to: url)
        return url
    }

    /// Mixed Hebrew and Latin, because both have to sit in the same list without either breaking
    /// the other's alignment.
    private static let srt = """
    1
    00:02:20,000 --> 00:02:23,000
    אני לא יודע מה לומר.

    2
    00:02:25,000 --> 00:02:28,000
    אז אל תגיד כלום.

    3
    00:02:32,000 --> 00:02:35,000
    זה בדיוק מה שחשבתי.

    4
    00:02:37,000 --> 00:02:40,000
    We can switch language mid-scene.

    5
    00:02:43,000 --> 00:02:46,000
    And the timecodes still line up.

    """
}


// MARK: - Home

/// The real `HomeScreen` over a fabricated `HomeStore`, so the preview header and every rail —
/// Continue Watching (part-way entries plus an up-next episode), Recently Added Movies and Recently
/// Added Shows — can be seen together, and a tile's press-and-hold menu opened, without a
/// signed-in session.
///
/// A watch history is the one fixture the simulator cannot cheaply produce: Continue Watching is
/// written by actually playing something, so an unseeded simulator renders a Home with no
/// Continue Watching rail at all, which is exactly the half of this screen worth looking at.
///
/// The titles are real rows out of the library snapshot, so the posters resolve, and the header
/// reads the real TMDB art (logos, textless backdrops) through a real `TitleArtStore` — the
/// preview session, never signed in, has none of its own.
///
/// `homefailed` shows the library-failure state instead: Try Again must be on screen and focused,
/// and pressing it must leave it focused, reading "Trying…". `homedownloading` adds a Downloading
/// rail with one download in flight, between Continue Watching and Recently Added;
/// `homedownloadsonly` has that download and nothing else.
///
/// `homepicks` is Home with Letterboxd set up: Continue Watching, then "Picked for Right Now" and
/// "Both of You Want to See" over the Watchlist harness's films (Noga as the partner, real TMDB
/// details for the header) — and no Recently Added rails. `homepicksdownloading` adds the
/// Downloading rail between Continue Watching and the picks; `homepicksonly` has no Continue
/// Watching, so Home must open on the first picked film. `homepicksslow` is `homepicks` with TMDB
/// answering 15 s late: a pick focused before its details land must get its synopsis in place.
/// `homepicksfirstrun` is a first run with nothing under way: no list yet and the day's first
/// crawl still running — Home must say so, not "Nothing here yet".
private struct HomeScreenPreview: View {
    var failure: String?
    var downloading = false
    /// `homedownloadsonly`: a download under way and nothing else — Home must open on its tile,
    /// with its header, rather than on no tile at all.
    var downloadsOnly = false
    /// `homepicks*`: the watchlist rows, as Home shows them with a Letterboxd username set.
    var picks = false
    /// `homepicksonly`: the watchlist rows and nothing else.
    var picksOnly = false
    /// `homepicksfirstrun`: the rows empty while the first list is made.
    var firstRun = false
    /// `homepicksarrive`: a first run as it really goes — Both at once (it needs no crawl), the
    /// day's picks 10s later, inserted above the row Home opened on.
    var arrive = false
    @State private var picksArrived = false
    /// No file, so Home's own fetch is what fills it — the way a first run goes.
    @State private var watchlistDetails: WatchlistDetailsStore

    init(failure: String? = nil, downloading: Bool = false, downloadsOnly: Bool = false,
         picks: Bool = false, picksOnly: Bool = false, slowDetails: Bool = false, firstRun: Bool = false,
         arrive: Bool = false) {
        self.failure = failure
        self.firstRun = firstRun
        self.arrive = arrive
        self.downloading = downloading
        self.downloadsOnly = downloadsOnly
        self.picks = picks
        self.picksOnly = picksOnly
        let service = TMDBDetailsService(client: TMDBClient(apiKey: Secrets.tmdbAPIKey))
        _watchlistDetails = State(initialValue: slowDetails
            ? WatchlistDetailsStore(fileURL: nil, publishEvery: 1) { id in
                try await Task.sleep(for: .seconds(15))
                return WatchlistFilmDetails(movie: try await service.movieDetails(tmdbID: id),
                                            fetchedAt: Date())
            }
            : WatchlistDetailsStore(fileURL: nil, details: service))
    }
    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))
    @State private var home = HomeStore(watch: PreviewWatch())
    /// The failed state's store: empty, so nothing but the failure is on screen.
    @State private var emptyHome = HomeStore(watch: PreviewWatch())
    @State private var art = TitleArtStore(details: TMDBDetailsService(
        client: TMDBClient(apiKey: Secrets.tmdbAPIKey)))
    @State private var ready = false

    var body: some View {
        NavigationStack {
            Group {
                if let failure {
                    HomeScreen(previewHome: emptyHome, previewArt: art, previewFailure: failure)
                } else if downloadsOnly {
                    HomeScreen(previewHome: emptyHome, previewArt: art,
                               previewDownloads: [DownloadPreviewFixture.dune])
                } else if picksOnly {
                    HomeScreen(previewHome: emptyHome, previewArt: art,
                               previewPicks: firstRun ? HomeWatchlistRows(isRefreshing: true)
                                   : arrive && !picksArrived ? Self.bothOnlyRows : Self.watchlistRows,
                               previewWatchlistDetails: watchlistDetails)
                } else if ready {
                    HomeScreen(previewHome: home, previewArt: art,
                               previewDownloads: downloading ? [DownloadPreviewFixture.dune] : nil,
                               previewPicks: picks ? Self.watchlistRows : nil,
                               previewWatchlistDetails: picks ? watchlistDetails : nil)
                } else {
                    Color.black
                }
            }
            // The shell's content inset, so x positions match the real app.
            .sideMenuContentInset()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CanvasBackground())      // the shell's own background
        }
        .environment(session)
        .task {
            home.activeProfileID = "preview"
            await home.rebuild(movies: Self.movies, shows: Self.shows)
            ready = true
        }
        .task {
            guard arrive else { return }
            try? await Task.sleep(for: .seconds(10))
            picksArrived = true
        }
    }

    /// `homepicksarrive` before the day's list: Both alone, as a first run opens.
    private static var bothOnlyRows: HomeWatchlistRows {
        var rows = watchlistRows
        rows.picked = []
        return rows
    }

    /// Picked: a run of films from both lists, Noga's only and the unmatched one among them (it
    /// still opens nothing and says "No TMDB match"). Both: every film on both lists.
    private static var watchlistRows: HomeWatchlistRows {
        let entries = WatchlistPreviewFixture.entries
        let picked = [15, 4, 16, 8, 2, 12, 9, 17, 5, 18, 0, 13].map { entries[$0] }
        let both = [6, 11, 15, 2].map { entries[$0] }
        return HomeWatchlistRows(picked: picked, both: both,
                                 membership: WatchlistMembership(owner: WatchlistPreviewFixture.owners,
                                                                 partner: WatchlistPreviewFixture.partners),
                                 partnerName: "Noga")
    }

    /// Two part-way entries, because the two kinds offer different menus — a movie is marked on its
    /// own, an episode names itself and adds the whole-series marks — and one finished episode, so
    /// its show comes back as the episode after it, "Next".
    private struct PreviewWatch: WatchProgressProviding {
        func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] {
            [WatchState(contentKey: "movie:tmdb:73", sourceKey: "t#1", positionSeconds: 1_920,
                        durationSeconds: 7_140, finished: false, updatedAt: Date()),
             WatchState(contentKey: "show:tmdb:95557:s3e1", sourceKey: "t#2", positionSeconds: 240,
                        durationSeconds: 2_700, finished: false, updatedAt: Date().addingTimeInterval(-60))]
        }
        func recentlyFinished(limit: Int, profileID: String) async throws -> [WatchState] {
            [WatchState(contentKey: "show:tmdb:95396:s1e1", sourceKey: "t#3", positionSeconds: 3_300,
                        durationSeconds: 3_300, finished: true, updatedAt: Date().addingTimeInterval(-120))]
        }
        func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { nil }
        func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                    durationSeconds: Double, finished: Bool, profileID: String) async throws {}
        func deleteProgress(forContentKeys keys: [String]) async throws {}
    }

    private static func source(_ id: String) -> MediaSource {
        MediaSource(torrentID: id, fileID: 1, restrictedLink: "rd://\(id)",
                    parsed: ParsedRelease(title: "T", resolution: "2160p"))
    }

    /// Sixty real rows out of the library snapshot, newest first — id, title, year, poster.
    ///
    /// Sixty DISTINCT posters because that is what a real library looks like — NOT, as this said
    /// before, because repeating one would strand the duplicates on a spinner. That was wrong, and
    /// measured wrong twice: sixty tiles over six posters all load (`ImageMemoryCache.load` hands
    /// the loser the winner's bitmap, or fetches again if the winner outruns its wait), and giving
    /// them colliding `ForEach` ids does not strand anything either — SwiftUI simply collapses the
    /// sixty elements into six views, so the grid comes out short rather than broken.
    private static let posters: [(String, String, Int, String)] = [
        ("movie:tmdb:73", "American History X", 1998, "/x2drgoXYZ8484lqyDj7L1CEVR4T.jpg"),
        ("movie:tmdb:762504", "Nope", 2022, "/AcKVlWaNVVVFQwro3nLXqPljcYA.jpg"),
        ("movie:tmdb:238", "The Godfather", 1972, "/3bhkrj58Vtu7enYsRolD1fZdja1.jpg"),
        ("movie:tmdb:340666", "Nocturnal Animals", 2016, "/mdLDgQBD0va09npSQX5Zgo2evXM.jpg"),
        ("movie:tmdb:103663", "The Hunt", 2012, "/jkixsXzRh28q3PCqFoWcf7unghT.jpg"),
        ("movie:tmdb:701387", "Bugonia", 2025, "/rSdOua3wKMEaFWDcKAYWRjXQWOt.jpg"),
        ("movie:tmdb:26513", "Punishment Park", 1971, "/fPGnMnp80ycqUHdgP1T3nzCyYKe.jpg"),
        ("movie:tmdb:406", "La Haine", 1995, "/hY4exng4s29RzDbtQInjx9MA3PZ.jpg"),
        ("movie:tmdb:26719", "House of Games", 1987, "/4i27Ut4cIoLbcNpW7aeuUQErEPE.jpg"),
        ("movie:tmdb:1592", "Primal Fear", 1996, "/qJf2TzE8nRTFbFMPJNW6c8mI0KU.jpg"),
        ("movie:tmdb:4553", "The Machinist", 2004, "/diAYqR4xdF9Hnj7qun6DEQhRrT2.jpg"),
        ("movie:tmdb:2649", "The Game", 1997, "/4UOa079915QjiTA2u5hT2yKVgUu.jpg"),
        ("movie:tmdb:655", "Paris, Texas", 1984, "/sP27Qm4THyRZyHjHYMfIDtJP6YE.jpg"),
        ("movie:tmdb:274", "The Silence of the Lambs", 1991, "/uS9m8OBk1A8eM9I042bx8XXpqAq.jpg"),
        ("movie:tmdb:62", "2001: A Space Odyssey", 1968, "/ve72VxNqjGM69Uky4WTo2bK6rfq.jpg"),
        ("movie:tmdb:28", "Apocalypse Now", 1979, "/gQB8Y5RCMkv2zwzFHbUJX3kAhvA.jpg"),
        ("movie:tmdb:117", "The Untouchables", 1987, "/tPq0R4jTO4Ey8ZspFaWK9wGA4Ls.jpg"),
        ("movie:tmdb:424", "Schindler's List", 1993, "/sF1U4EUQS8YHUYjNl3pMGNIQyr0.jpg"),
        ("movie:tmdb:380", "Rain Man", 1988, "/iTNHwO896WKkaoPtpMMS74d8VNi.jpg"),
        ("movie:tmdb:500", "Reservoir Dogs", 1992, "/xi8Iu6qyTfyZVDVy60raIOYJJmk.jpg"),
        ("movie:tmdb:968", "Dog Day Afternoon", 1975, "/mavrhr0ig2aCRR8d48yaxtD5aMQ.jpg"),
        ("movie:tmdb:510", "One Flew Over the Cuckoo's Nest", 1975, "/kjWsMh72V6d8KRLV4EOoSJLT1H7.jpg"),
        ("movie:tmdb:1018", "Mulholland Drive", 2001, "/x7A59t6ySylr1L7aubOQEA480vM.jpg"),
        ("movie:tmdb:769", "GoodFellas", 1990, "/9OkCLM73MIU2CrKZbqiT8Ln1wY2.jpg"),
        ("movie:tmdb:98", "Gladiator", 2000, "/wN2xWp1eIwCKOD0BHTcErTBv1Uq.jpg"),
        ("movie:tmdb:7345", "There Will Be Blood", 2007, "/fa0RDkAlCec0STeMNAhPaF89q6U.jpg"),
        ("movie:tmdb:77016", "End of Watch", 2012, "/pDeVKQICkcdwwjHxGj0MeS14YJ6.jpg"),
        ("movie:tmdb:496243", "Parasite", 2019, "/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg"),
        ("movie:tmdb:901563", "Close", 2022, "/dlMNnWs7Mz8Nk5AC447Ew1tD5pn.jpg"),
        ("movie:tmdb:670", "Oldboy", 2003, "/pWDtjs568ZfOTMbURQBYuT4Qxka.jpg"),
        ("movie:tmdb:206487", "Predestination", 2014, "/38Xr1JnV1ZcLQ55zmdSp6n475cZ.jpg"),
        ("movie:tmdb:598", "City of God", 2002, "/k7eYdWvhYQyRQoU2TB2A2Xu2TfD.jpg"),
        ("movie:tmdb:1417", "Pan's Labyrinth", 2006, "/z7xXihu5wHuSMWymq5VAulPVuvg.jpg"),
        ("movie:tmdb:950396", "The Gorge", 2025, "/7iMBZzVZtG0oBug4TfqDb9ZxAOa.jpg"),
        ("movie:tmdb:451915", "Beautiful Boy", 2018, "/u2Gfv0mz3xePsgyCPHovrnFL1sB.jpg"),
        ("movie:tmdb:11104", "Chungking Express", 1994, "/43I9DcNoCzpyzK8JCkJYpHqHqGG.jpg"),
        ("movie:tmdb:1422", "The Departed", 2006, "/nT97ifVT2J1yMQmeq20Qblg61T.jpg"),
        ("movie:tmdb:103", "Taxi Driver", 1976, "/ekstpH614fwDX8DUln1a2Opz0N8.jpg"),
        ("movie:tmdb:648878", "Eddington", 2025, "/4GIqZUgPZ146BhibsPHMHef2nXX.jpg"),
        ("movie:tmdb:272", "Batman Begins", 2005, "/sPX89Td70IDDjVr85jdSBb4rWGr.jpg"),
        ("movie:tmdb:155", "The Dark Knight", 2008, "/qJ2tW6WMUDux911r6m7haRef0WH.jpg"),
        ("movie:tmdb:567748", "The Guilty", 2021, "/m8aR1k35oZMOzZ1kYWUyt401mwq.jpg"),
        ("movie:tmdb:890980", "God's Crooked Lines", 2022, "/n3X9tWYFYfE96BoNgtVffuwzQo.jpg"),
        ("movie:tmdb:131631", "The Hunger Games: Mockingjay - Part 1", 2014, "/4FAA18ZIja70d1Tu5hr5cj2q1sB.jpg"),
        ("movie:tmdb:101299", "The Hunger Games: Catching Fire", 2013, "/vrQHDXjVmbYzadOXQ0UaObunoy2.jpg"),
        ("movie:tmdb:577922", "Tenet", 2020, "/aCIFMriQh8rvhxpN1IWGgvH0Tlg.jpg"),
        ("movie:tmdb:1083381", "Backrooms", 2026, "/rhGx6E3qRNMgj3i5su2oukNHwIQ.jpg"),
        ("movie:tmdb:70160", "The Hunger Games", 2012, "/apa5G43Hha7kH7wJG0gkkHT7FA9.jpg"),
        ("movie:tmdb:336843", "Maze Runner: The Death Cure", 2018, "/s8K0US4tUEoOrQ1LDh0eppuwGDx.jpg"),
        ("movie:tmdb:10138", "Iron Man 2", 2010, "/6WBeq4fCfn7AN0o21W9qNcRF2l9.jpg"),
        ("movie:tmdb:294254", "Maze Runner: The Scorch Trials", 2015, "/mYw7ZyejqSCPFlrT2jHZOESZDU3.jpg"),
        ("movie:tmdb:1368337", "The Odyssey", 2026, "/5rhTDKUhPYvpdQIijFIs5VoWsON.jpg"),
        ("movie:tmdb:1726", "Iron Man", 2008, "/78lPtwv72eTNqFW9COBYI0dWDJa.jpg"),
        ("movie:tmdb:1325734", "The Drama", 2026, "/rnIOUhzwJDfgQakx8EjoNyItKgs.jpg"),
        ("movie:tmdb:696506", "Mickey 17", 2025, "/edKpE9B5qN3e559OuMCLZdW1iBZ.jpg"),
        ("movie:tmdb:503919", "The Lighthouse", 2019, "/yAKNmpcUweGH6WMCEWenwU9PsbE.jpg"),
        ("movie:tmdb:559", "Spider-Man 3", 2007, "/qFmwhVUoUSXjkKRmca5yGDEXBIj.jpg"),
        ("movie:tmdb:315635", "Spider-Man: Homecoming", 2017, "/c24sv2weTHPsmDa7jEMN0m2P3RT.jpg"),
        ("movie:tmdb:433808", "The Ritual", 2017, "/9022CYEGqYETCeXN1oE3uwYJWub.jpg"),
        ("movie:tmdb:1124", "The Prestige", 2006, "/Ag2B2KHKQPukjH7WutmgnnSNurZ.jpg")
    ]

    /// The grid's full capacity, because what is being verified is what a full page looks like.
    private static var movies: [MediaItem] {
        posters.enumerated().map { i, row in
            let (id, title, year, poster) = row
            let tmdb = Int(id.split(separator: ":").last ?? "")
            return MediaItem(id: id, kind: .movie, title: title, year: year,
                             sources: [source("t\(i)")], seasons: [], tmdbID: tmdb, posterPath: poster,
                             overview: tmdb.flatMap { overviews[$0] },
                             addedAt: Date().addingTimeInterval(-Double(i) * 3_600))
        }
    }

    /// Enough shows for a Recently Added Shows rail that runs off the screen, the first two also
    /// behind Continue Watching entries (INVINCIBLE part-way, Severance up next).
    private static var shows: [MediaItem] {
        let rows: [(Int, String, Int, String)] = [
            (95557, "INVINCIBLE", 2021, "/4tblBrslcKSifMVZ3TmtT2ukMor.jpg"),
            (95396, "Severance", 2022, "/pPHpeI2X1qEd1CS1SeyrdhZ4qnT.jpg"),
            (247718, "MobLand", 2025, "/5Xc7WpWsgflfgEMoBlf9TmWhfbH.jpg"),
            (153312, "Tulsa King", 2022, "/rOYLWCdAifpUtPlTf1WHxyaxeMt.jpg"),
            (203857, "The Diplomat", 2023, "/cUy0ZYme43lop08nOtbQLWL0dX.jpg"),
            (123542, "LINK CLICK", 2021, "/hCt2bLRGTCjHGqtV5FP3Img6w1h.jpg"),
            (30984, "Bleach", 2004, "/2EewmxXe72ogD0EaWM8gqa0ccIw.jpg"),
            (37854, "One Piece", 1999, "/dB4EDhre2dsC2kxYDavyKWqLQwi.jpg"),
        ]
        return rows.enumerated().map { i, row in
            let (tmdb, title, year, poster) = row
            let episodes = [Episode(season: 1, number: 1, source: source("t-\(tmdb)-1")),
                            Episode(season: 1, number: 2, source: source("t-\(tmdb)-2"))]
            let seasons = tmdb == 95557
                ? [Season(number: 3, episodes: [Episode(season: 3, number: 1, source: source("t-inv"))])]
                : [Season(number: 1, episodes: episodes)]
            return MediaItem(id: "show:tmdb:\(tmdb)", kind: .show, title: title, year: year,
                             sources: [], seasons: seasons, tmdbID: tmdb, posterPath: poster,
                             overview: overviews[tmdb],
                             addedAt: Date().addingTimeInterval(-Double(i) * 5_400))
        }
    }

    /// Library rows carry their synopsis; these are the ones the header shows at launch and on the
    /// first moves along Continue Watching.
    private static let overviews: [Int: String] = [
        73: "A former neo-Nazi skinhead tries to keep his younger brother from following the same path that sent him to prison.",
        95557: "Mark Grayson is a normal teenager — except his father is the most powerful superhero on the planet.",
        95396: "Mark leads a team of office workers whose memories have been surgically divided between their work and personal lives.",
    ]
}


/// Downloads in flight, for the Home rail and the My Library strip.
enum DownloadPreviewFixture {
    static let dune = tile(693134, "Dune: Part Two", poster: "/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg",
                           fraction: 0.42, secondsRemaining: 540)
    /// No poster: the title on a surface, never a blank card.
    static let noArt = tile(0, "גבעת חלפון אינה עונה", poster: nil, fraction: 0.08, secondsRemaining: nil)

    static func tile(_ tmdbID: Int, _ title: String, poster: String?, fraction: Double,
                     secondsRemaining: TimeInterval?) -> DownloadTile {
        DownloadTile(tmdbID: tmdbID, title: title, posterPath: poster,
                     status: DownloadStatus(torrentID: "dl-\(tmdbID)", contentKey: "movie:tmdb:\(tmdbID)",
                                            tmdbID: tmdbID, phase: .downloading, fraction: fraction,
                                            speedBytesPerSecond: 12_000_000,
                                            secondsRemaining: secondsRemaining,
                                            title: title, posterPath: poster))
    }
}

/// `-uiPreview downloadstrip`: My Library's Downloading strip with the rail-sized cards, over the
/// shell's background and inset, so its spacing and focus lift can be checked without a download.
private struct DownloadStripPreview: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                DownloadingStrip(tiles: [DownloadPreviewFixture.dune, DownloadPreviewFixture.noArt],
                                 library: nil)
                Spacer()
            }
            .padding(.top, 60)
            .sideMenuContentInset()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CanvasBackground())
        }
    }
}


// MARK: - Watchlist

/// The real `WatchlistScreen` on a fabricated model, so the page can be checked against Home's
/// without a Letterboxd account or a signed-in session.
///
/// The fixture exercises every row: films in the library (the grey ✓), films only Noga holds and
/// films on both lists (the chips), pre-1980 classics, short films, and one that resolved to
/// nothing (the Not Matched row). Real TMDB ids and poster paths, and a details store over the real
/// TMDB API (no file, so it fetches each run), so the genre, rating and runtime rows fill in the
/// way they do on a first visit.
private struct WatchlistScreenPreview: View {
    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))
    @State private var model: WatchlistModel

    private var removeFocusedAfter: Duration?

    init(partnerUnreadable: Bool = false, slowDetails: Bool = false, removeFocusedAfter: Duration? = nil) {
        self.removeFocusedAfter = removeFocusedAfter
        _model = State(initialValue: Self.makeModel(partnerUnreadable: partnerUnreadable))
        if slowDetails {
            let service = TMDBDetailsService(client: TMDBClient(apiKey: Secrets.tmdbAPIKey))
            _details = State(initialValue: WatchlistDetailsStore(fileURL: nil, publishEvery: 6) { id in
                try await Task.sleep(for: .seconds(3))
                return WatchlistFilmDetails(movie: try await service.movieDetails(tmdbID: id),
                                            fetchedAt: Date())
            })
        }
    }

    @State private var art = TitleArtStore(details: TMDBDetailsService(
        client: TMDBClient(apiKey: Secrets.tmdbAPIKey)))
    @State private var details = WatchlistDetailsStore(
        fileURL: nil, details: TMDBDetailsService(client: TMDBClient(apiKey: Secrets.tmdbAPIKey)))

    var body: some View {
        NavigationStack {
            WatchlistScreen(previewModel: model, previewArt: art, previewDetails: details,
                            previewRemoveFocusedAfter: removeFocusedAfter)
                // A root page: the shell's content inset, so x positions match the real app.
                .sideMenuContentInset()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationDestination(for: BrowseDestination.self) { _ in Color.black }
        }
            .environment(session)
            // The screen's own `.task` does not run in preview mode, so the status is read here.
            .task {
                await model.refreshStatus()
                await model.pushPending()
            }
    }

    private static func makeModel(partnerUnreadable: Bool) -> WatchlistModel {
        let partner = WatchlistCombinedStatus(
            membership: WatchlistMembership(owner: WatchlistPreviewFixture.owners,
                                            partner: WatchlistPreviewFixture.partners),
            partnerName: "Noga",
            partnerError: partnerUnreadable
                ? "Couldn't read Noga's watchlist — the profile is private, renamed or gone." : nil)
        let model = WatchlistModel(cached: WatchlistPreviewFixture.entries,
                                   settings: LetterboxdSettings(username: "preview"),
                                   relay: {
                                       partnerUnreadable
                                           ? .init(pushed: 0, failed: 1,
                                                   firstError: "Couldn't reach SeretServer to remove Speed.")
                                           : .idle
                                   },
                                   status: { partner }) { _ in
            WatchlistPreviewFixture.entries
        }
        // Four of them are already in the library: Stalker, Eraserhead, Parasite, Heat.
        model.ownedTMDBIDs = [1398, 985, 496243, 949]
        return model
    }

}

/// File scope, not a nested static: the view is `@MainActor`, and the model's sync closure is
/// `@Sendable` — a fixture read from inside it must not be actor-isolated.
private enum WatchlistPreviewFixture {
    /// Name, year, TMDB id, poster, and whose list: "o" the owner's, "p" Noga's, "b" both.
    static let films: [(String, Int, Int?, String?, Character)] = [
        ("Stalker (1979)", 1979, 1398, "/1qhOyf5C4s9ZdvY8d5JDx9DFMeT.jpg", "o"),
        ("Eraserhead (1977)", 1977, 985, "/mxveW3mGVc0DzLdOmtkZsgd7c3B.jpg", "o"),
        ("American Beauty (1999)", 1999, 14, "/wby9315QzVKdW9BonAefg8jGTTb.jpg", "b"),
        ("Honey Don't! (2025)", 2025, 1149504, "/fJm3kmd9NLZWypMas7g34oNFgbk.jpg", "o"),
        ("Mother (2009)", 2009, 30018, "/8oBnSkZE6GDVugAbLPO6uJd4GcS.jpg", "p"),
        ("Ocean's Eleven (2001)", 2001, 161, "/hQQCdZrsHtZyR6NbKH2YyCqd2fR.jpg", "o"),
        ("Grave of the Fireflies (1988)", 1988, 12477, "/k9tv1rXZbOhH7eiCk378x61kNQ1.jpg", "b"),
        ("Parasite (2019)", 2019, 496243, "/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg", "o"),
        ("Incendies (2010)", 2010, 46738, "/yH6DAQVgbyj72S66gN4WWVoTjuf.jpg", "p"),
        ("The Brutalist (2024)", 2024, 549509, "/vP7Yd6couiAaw9jgMd5cjMRj3hQ.jpg", "o"),
        ("It's a Wonderful Life (1946)", 1946, 1585, "/bSqt9rhDZx1Q7UZ86dBPKdNomp2.jpg", "p"),
        ("Anora (2024)", 2024, 1064213, "/cgXk2tNYhJZLXdBDO5DidAVzQ82.jpg", "b"),
        ("Nosferatu (2024)", 2024, 426063, "/5qGIxdEO841C0tdY8vOdLoRVrr0.jpg", "o"),
        ("Heat (1995)", 1995, 949, "/umSVjVdbVwtx5ryCA2QXL44Durm.jpg", "o"),
        ("Speed (1994)", 1994, 1637, "/82PkCE4R95KhHICUDF7G4Ly2z3l.jpg", "o"),
        ("Whiplash (2014)", 2014, 244786, "/7fn624j5lj3xTme2SgiLCeuedmO.jpg", "b"),
        ("Arrival (2016)", 2016, 329865, "/pEzNVQfdzYDzVK0XqxERIw2x2se.jpg", "o"),
        ("Dune (2021)", 2021, 438631, "/v1tRXZ4JtD2Iv6fjkPvT4GiwslV.jpg", "p"),
        // Resolved and found nothing — the Not Matched row.
        ("A Film TMDB Has Never Heard Of (2019)", 2019, nil, nil, "o"),
    ]

    static var entries: [WatchlistEntry] {
        films.enumerated().map { index, film in
            WatchlistEntry(slug: "f\(index)", name: film.0, year: film.1, position: index,
                           tmdbID: film.2, posterPath: film.3, resolvedAt: Date())
        }
    }

    static var owners: [WatchlistEntry] { pick { $0 == "o" || $0 == "b" } }
    static var partners: [WatchlistEntry] { pick { $0 == "p" || $0 == "b" } }

    private static func pick(_ holder: (Character) -> Bool) -> [WatchlistEntry] {
        zip(films, entries).filter { holder($0.0.4) }.map(\.1)
    }
}


// MARK: - Letterboxd settings card

/// The Settings Letterboxd card in the state the owner actually has: a username synced from the
/// iPhone, but "Import my ratings" never switched on there.
///
/// Sandwiched between two cards that definitely take focus, because the question is not what the
/// card looks like — it is whether the remote can land on it at all. Walk DOWN from the top card
/// The confirmation over a stand-in for the picture. It re-fires on a loop so a screenshot can
/// land inside the three seconds it is up — and so the re-fire path, which a rewatch takes, is
/// exercised rather than assumed.
private struct LetterboxdToastPreview: View {
    @State private var signal = LetterboxdPushSignal()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text("the film, playing")
                .font(.seret(28, .regular))
                .foregroundStyle(.white.opacity(0.28))
        }
        .letterboxdDiaryBar(signal: signal, contentKey: "movie:tmdb:73") { state in
            switch state {
            case .logged: LetterboxdLoggedBar()
            case .askingRating: EmptyView()      // its own case below
            }
        }
        .task {
            while !Task.isCancelled {
                signal.logged(tmdbID: 73)
                try? await Task.sleep(for: .milliseconds(3500))
            }
        }
    }
}

/// The post-credits rating prompt, over a stand-in for the picture.
///
/// Static — no loop — because the question here is whether the remote can reach the stars and
/// which one it lands on, and a bar that re-mounts every few seconds would keep stealing focus
/// back mid-walk. `-uiPreview letterboxdrating` for an unrated film; the second case below is
/// the one that matters for a rewatch.
private struct LetterboxdRatingPreview: View {
    let existing: Int?
    /// Show the prompt as it first arrives — the invitation, before Up — instead of the stars.
    var invite = false
    @State private var signal = LetterboxdPushSignal()
    @State private var picked: String = "nothing picked yet"
    @FocusState private var focus: PlayerFocus?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("the film, playing")
                    .font(.seret(28, .regular))
                    .foregroundStyle(.white.opacity(0.28))
                // The measurable part: a screenshot says what the press actually produced,
                // rather than leaving it to be inferred from the stars.
                Text(picked)
                    .font(.seret(22, .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
        }
        .letterboxdDiaryBar(signal: signal, contentKey: "movie:tmdb:73") { state in
            switch state {
            case .logged: LetterboxdLoggedBar()
            case .askingRating(_, let current):
                if invite {
                    LetterboxdRatingInvite(current: current)
                } else {
                    LetterboxdRatingBar(current: current, focus: $focus) { value in
                        picked = value.map { "rated \($0)/10" } ?? "rating cleared"
                    } onDismiss: {
                        picked = "dismissed — logged unrated"
                    }
                }
            }
        }
        .onExitCommand { picked = "dismissed — logged unrated" }
        .task { signal.askForRating(tmdbID: 73, current: existing) }
    }
}

/// A browser that has been signed out, for the preview above: the failure the owner most needs
/// the card to explain, and the one that stops the drain.
private struct AlwaysSignedOutRelay: LetterboxdRelaying {
    func send(_ write: LetterboxdWrite) async throws { throw LetterboxdError.notAuthenticated }
}

/// and see where focus ends up.
private struct LetterboxdCardPreview: View {
    @State private var help = SettingsHelp()
    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))
    @State private var model = LetterboxdImportModel(
        settingsStore: InMemoryLetterboxdSettingsStore(
            LetterboxdSettings(username: "thebigshin", isEnabled: false,
                               serverURL: "192.168.1.179:8080",
                               partnerUsername: "nogap", partnerName: "Noga")),
        run: { _, _ in LetterboxdImporter.Summary(scanned: 0, needingWork: 0, written: 0,
                                                  conflicts: 0, unresolved: 0) })

    /// A queue that cannot drain, so the status rows have something to say. A fixture that leaves
    /// them empty would render the card exactly as it looked before and prove nothing.
    @State private var push = LetterboxdPushCoordinator(
        outbox: InMemoryLetterboxdOutbox([
            LetterboxdWrite(tmdbID: 73, rating: 9, watchedAt: Date()),
            LetterboxdWrite(tmdbID: 550, rating: nil, watchedAt: Date())
        ]),
        relay: AlwaysSignedOutRelay(),
        loggedElsewhere: { _ in false },
        isEnabled: { true })

    var body: some View {
        SettingsPageLayout(title: "Letterboxd", clearsSideMenu: true) {
            SettingsHelpPane(content: help.current)
        } rows: {
            SettingsSectionHeader(title: "Above", first: true)
            SettingsRow(title: "Focusable above") {}
            LetterboxdSettingsSection(model: model, profileID: "preview-profile", push: push)
            SettingsSectionHeader(title: "Below")
            SettingsRow(title: "Focusable below") {}
        }
        .environment(help)
        // `LetterboxdSettingsSection` reads `AppSession` non-optionally, and a missing one is a fatalError
        // rather than a blank view — this harness rendered pure black until it was provided.
        // See the Settings card's own environment read.
        .environment(session)
        .task {
            // Drain once so `lastError` is populated, not just the pending count.
            await push.drain()
            await model.refreshPushStatus(from: push)
        }
    }
}

/// A settings store that keeps the value in memory — the preview must not touch iCloud or the
/// device's real defaults.
private final class InMemoryLetterboxdSettingsStore: LetterboxdSettingsStoring, @unchecked Sendable {
    private var settings: LetterboxdSettings
    init(_ settings: LetterboxdSettings) { self.settings = settings }
    func load() -> LetterboxdSettings { settings }
    func save(_ settings: LetterboxdSettings) { self.settings = settings }
}


// MARK: - Watchlist randomiser

/// The Cover Flow reel on the same real posters the watchlist preview uses, so the spin, the white
/// frame, the backdrop fading in and the landed result can be watched without a Letterboxd
/// account. `-uiPreview spin` always lands on Whiplash, with its real TMDB backdrop and logo, so
/// screenshots are comparable run to run (it spins for ~3.4 s once the posters are in, so a
/// screenshot ~2 s after launch catches it mid-turn); `-uiPreview spinnoart` lands with no art at
/// all — the text title on the plain background. "Spin Again" re-runs the same landing, which is
/// also the check that a re-spin onto the same film restarts the reel.
private struct WatchlistSpinPreview: View {
    var withArt = true
    @State private var spin = Self.fixedSpin()

    /// Whiplash's TMDB art, fetched once from TMDB for this fixture.
    private static let whiplashBackdrop = "/fRGxZuo7jJUWQsVg9PREb98Aclp.jpg"
    private static let whiplashLogo = "/kTmh3W4iWQnNUcnYNgxgOVhpzCe.png"

    private static func fixedSpin() -> WatchlistRandomizer.Spin {
        // Only films with a poster ride the reel, as `WatchlistRandomizer` builds it.
        let films = WatchlistPreviewFixture.entries.filter { $0.posterPath != nil }
        let reel = (0..<34).map { films[$0 % films.count] }
        let winnerIndex = reel.indices.last { reel[$0].tmdbID == 244786 && $0 <= 30 } ?? 30
        return WatchlistRandomizer.Spin(winner: reel[winnerIndex], reel: reel, winnerIndex: winnerIndex)
    }

    var body: some View {
        WatchlistSpinScreen(spin: spin, details: nil, onWatch: { _ in },
                            onSpinAgain: { spin = Self.fixedSpin() }, onClose: {},
                            artOverride: withArt
                                ? (backdropPath: Self.whiplashBackdrop, logoPath: Self.whiplashLogo)
                                : (backdropPath: nil, logoPath: nil))
    }
}


// MARK: - Server reachability

/// Answers one question: can this device reach SeretServer, and if not, who refused?
///
/// A watchlist removal reported "Couldn't reach your Seret server" while the server was up and
/// answering curl from the same LAN. The cause was App Transport Security refusing the cleartext
/// request — the app never made the call. That is invisible from the server side and looks
/// identical to a dead NAS, so it needs to be asked from inside the app process.
private struct ServerReachabilityPreview: View {
    @State private var lines: [String] = ["probing…"]

    /// Both the address that failed for real and the one that works, so the two messages can be
    /// read side by side. Driving this by hand through the focus engine costs minutes per attempt;
    /// running it on appear makes the answer a screenshot.
    private static let cases = [("192.168.1.179:8000", "the port that was actually typed"),
                                ("192.168.1.179:8080", "the right one"),
                                ("192.168.1.42:8080", "a host that is not there")]

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(alignment: .leading, spacing: 16) {
                Text("Test Connection — what it says").sectionTitle()
                    .foregroundStyle(Theme.Palette.textPrimary)
                ForEach(lines, id: \.self) { line in
                    Text(line).calloutText().foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .padding(Theme.Layout.contentMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await probe() }
    }

    private func probe() async {
        let http = HTTPClient()
        var out: [String] = []
        for (address, note) in Self.cases {
            let test = ServerConnectionTest(address: address,
                                            probe: { url in _ = try await http.data(url) })
            await test.run()
            switch test.result {
            case .reachable(let a): out.append("✅ \(a) — reached  (\(note))")
            case .failed(let m):    out.append("❌ \(address) — \(m)")
            default:                out.append("• \(address) — \(String(describing: test.result))")
            }
            lines = out
        }
    }
}

// MARK: - A page inside the side menu

/// `-uiPreview homemenu` / `browsemenu` / `watchlistmenu`: the real page beside the real side menu,
/// wired as the shell wires them (focus entering the menu opens it, leaving closes it), so the
/// remote walk "focus a tile mid-rail, Left into the menu, Right back" can be run without a
/// signed-in session. Right must land on the tile that was left — the page's focus memory,
/// through `FocusBrowseHandle`.
private struct MenuWrappedPreview<Page: View>: View {
    @ViewBuilder var page: Page

    @FocusState private var focus: SideMenuItem?
    @State private var expanded = false

    var body: some View {
        ZStack(alignment: .leading) {
            page.focusSection()
            SideMenuScrim(visible: expanded)
            SideMenu(selected: .home, profileName: "Shahar",
                     profileAvatar: "", profileColorTag: Theme.Palette.defaultColorTag,
                     focus: $focus, expanded: expanded,
                     onSelect: { _ in expanded = false }, onProfile: {})
        }
        .onChange(of: focus) { _, new in expanded = new != nil }
        // Menu opens the side menu from anywhere, as in the shell.
        .onExitCommand(perform: expanded ? nil : { focus = .home })
    }
}

#endif
