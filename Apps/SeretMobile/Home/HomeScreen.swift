import DebridCore
import DebridUI
import SwiftUI

/// Home, as the mockups (g1 iPhone, m5 iPad) and the Apple TV draw it: a full-bleed hero for the
/// title you were last watching, then sideways poster rails — Continue Watching, Downloading
/// (while anything is), then "Picked for Right Now" and "Both of You Want to See" from the
/// Letterboxd watchlists (`session.homePicks`) — composed on `session.home`. With no Letterboxd
/// username set up, Recently Added Movies and Recently Added Shows take the watchlist rows' place.
///
/// The hero is the first Continue Watching entry; with nothing under way, the first picked film
/// (else the first you both want to see), or without Letterboxd the newest arrival.
///
/// - iPhone: the art runs under the status bar and the glass header ("Seret", Search, Settings);
///   the header's shade only firms up once the hero has scrolled away.
/// - iPad: the art runs the page's width and on under the floating sidebar
///   (`shellLeadingInset`), with the preview (logo, metadata, synopsis, buttons) on the left.
///
/// Resume plays directly (the title's page only when its file no longer resolves); a tile in
/// Continue Watching resumes too and keeps its long-press marks; Recently Added tiles open the
/// title's page and keep the library menu; Downloading tiles open the page of what is landing;
/// watchlist films open their title page, owned or not, with no long-press Remove (the Watchlist
/// page owns removal) and no See All.
struct HomeScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(AppRouter.self) private var router
    /// iPad: the shell draws the hero art behind the floating sidebar; Home reports its scroll
    /// and hides it under a pushed page. Optional — absent outside the shell.
    @Environment(HomeBackdropModel.self) private var shellBackdrop: HomeBackdropModel?
    /// Home's own stack — a page pushed over it (See All) hides the shell's art.
    @State private var navPath = NavigationPath()
    /// The page's last scroll offset, so the shell's art can be put back where the page is when
    /// Home reappears (the scroll handler only fires on a CHANGE). A plain reference box, not
    /// `@State` of a value: it is written on every scroll frame, and a state write would
    /// re-evaluate Home's whole body (every rail) per frame.
    @State private var scrollMemory = ScrollMemory()
    @State private var showingProfiles = false
    @State private var showingSettings = false
    /// A title awaiting removal confirmation, and the failure to surface if RD refuses.
    @State private var pendingRemoval: MediaItem?
    @State private var removeErrorMessage: String?
    /// The hero has scrolled (mostly) away — the iPhone header's shade firms up for the posters.
    @State private var pastHero = false
    /// The watchlist films' TMDB details (synopsis, plate, logo) for a picked hero — the store the
    /// Watchlist page fills. Set once Home appears, never made in the body: making it registers it
    /// on the session.
    @State private var watchlistDetails: WatchlistDetailsStore?
    /// `HomePicksStore.load()` has answered once — until then "nothing on Home" is not yet known.
    @State private var picksLoaded = false
    /// OPTIONAL, deliberately — see `HitTile`.
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?

#if DEBUG
    /// Fixture stores from a `-uiPreview` harness (see `PagesUIPreview`), else the session's.
    @Environment(\.uiPreviewStores) private var preview
    private var homeStore: HomeStore? { preview?.home ?? session.home }
    private var art: TitleArtStore? { preview?.art ?? session.titleArt }
    private var activeDownloads: [DownloadTile] {
        preview?.downloads ?? session.downloadStore?.activeTiles ?? []
    }
    /// Home's watchlist rows. Nil when no Letterboxd username is set — Home then shows Recently
    /// Added instead.
    private var watchlistRows: HomeWatchlistRows? {
        preview?.homePicks ?? session.homePicks.map(HomeWatchlistRows.init)
    }
    private var injectedWatchlistDetails: WatchlistDetailsStore? { preview?.watchlistDetails }
#else
    private var homeStore: HomeStore? { session.home }
    private var art: TitleArtStore? { session.titleArt }
    private var activeDownloads: [DownloadTile] { session.downloadStore?.activeTiles ?? [] }
    private var watchlistRows: HomeWatchlistRows? { session.homePicks.map(HomeWatchlistRows.init) }
    private var injectedWatchlistDetails: WatchlistDetailsStore? { nil }
#endif

    private var isRegular: Bool { hSize == .regular }
    private var margin: CGFloat { PosterTileMetrics.margin(hSize) }

    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack(alignment: .top) {
                // On iPad the shell's art layer IS the background (see `HomeBackdropModel`).
                if !(isRegular && shellBackdrop != nil) { CanvasBackground() }
                content
                if !isRegular { header }
            }
            .toolbar(.hidden, for: .navigationBar)
            // The stack paints an opaque page background of its own; on iPad the shell's art
            // must show through it.
            .containerBackground(isRegular && shellBackdrop != nil ? Color.clear : Theme.Palette.canvas,
                                 for: .navigation)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .recentlyAdded(let kind): RecentlyAddedGrid(kind: kind)
                }
            }
            .libraryRemovalConfirmation(pending: $pendingRemoval,
                                        errorMessage: $removeErrorMessage,
                                        store: session.libraryStore)
        }
        // The shell's art follows Home's stack: hidden under a pushed page, shown at the root —
        // asserted on every appearance too, since a tab switch from a pushed page and back
        // re-creates the page without the stack's emptiness ever "changing".
        .onChange(of: navPath.isEmpty, initial: true) { _, atRoot in shellBackdrop?.hidden = !atRoot }
        .onAppear {
            shellBackdrop?.hidden = !navPath.isEmpty
            shellBackdrop?.offset = scrollMemory.offset
        }
        // Leaving Home (another section) — the next Home starts at the top, so must the art.
        .onDisappear { shellBackdrop?.offset = 0 }
#if DEBUG
        // `-uiPreview homescript` pushes and pops Home's own stack.
        .onChange(of: preview?.homeScript?.pushes) { _, _ in navPath.append(HomeRoute.recentlyAdded(.movie)) }
        .onChange(of: preview?.homeScript?.pops) { _, _ in if !navPath.isEmpty { navPath.removeLast() } }
#endif
        .fullScreenCover(isPresented: $showingProfiles) {
            WhoIsWatchingScreen(onPicked: { showingProfiles = false }).environment(session)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .environment(session)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingSettings = false }.tint(Theme.Palette.focus)
                        }
                    }
            }
        }
        .task {
            await session.libraryStore?.load()
            await rebuild()
        }
        // The watchlist rows: the day's cached picks and the mirrors at once, the day's refresh in
        // the background (store-owned, so it outlives this task). Again when the Letterboxd
        // account changes, which replaces the store.
        .task(id: session.homePicks.map(ObjectIdentifier.init)) {
            // A replaced store (the account changed) has not answered yet: without this, Home said
            // "Nothing here yet" until it had.
            picksLoaded = false
            if watchlistDetails == nil {
                watchlistDetails = injectedWatchlistDetails ?? session.makeWatchlistDetailsStore()
            }
            await session.homePicks?.load()
            picksLoaded = true
        }
        // The details of the films on Home's rows — a picked hero's synopsis, plate and logo.
        // Fetched here rather than left to the Watchlist page's preload, which walks the whole
        // list. Again for a new day's list; the store skips what it already has.
        .task(id: watchlistDetailIDs) {
            guard !watchlistDetailIDs.ids.isEmpty else { return }
            await watchlistDetails?.ensure(watchlistDetailIDs.ids)
        }
        .onChange(of: session.libraryStore?.movies) { _, _ in Task { await rebuild() } }
        .onChange(of: session.libraryStore?.shows) { _, _ in Task { await rebuild() } }
        // The active profile resolves asynchronously after sign-in; rebuild once it's known —
        // the watchlist rows too, which leave out what the profile has finished.
        .onChange(of: session.activeProfileID) { _, _ in
            Task {
                await rebuild()
                await session.homePicks?.load()
            }
        }
        // Re-enter the Home tab (e.g. after watching something) → refresh Continue Watching.
        .onAppear { Task { await rebuild() } }
        // The player is presented above the shell, so dismissing it doesn't fire onAppear here —
        // rebuild when it closes so the resume position / Continue Watching order update.
        .onChange(of: router.playback == nil) { _, closed in if closed { Task { await rebuild() } } }
        // …and the same for a title page, which is presented above the shell too: a title marked
        // watched (or played) there stayed on Continue Watching, unticked, until something else
        // happened to rebuild Home.
        .onChange(of: router.detail == nil) { _, closed in
            guard closed else { return }
            Task {
                await session.libraryStore?.reloadWatchStates()
                await rebuild()
            }
        }
    }

    // MARK: Header (iPhone)

    /// "Seret" + Search + Settings over the art. Its shade stays faint over the hero, so the art
    /// reads through as in the mockup, and firms up once the hero has scrolled away.
    private var header: some View {
        // Faint only while hero art is under it; firm once that has scrolled away — or when there
        // is no hero at all (only downloads), so the first rail never shows through.
        let overArt = homeStore.map { heroSubject($0, picks: watchlistRows) != nil } ?? false
        return GlassPageHeader(title: "Seret", shade: pastHero || !overArt ? 1 : 0.3) {
            SearchCircleLink()
            GlassCircleButton(systemImage: "gearshape", label: "Settings") { showingSettings = true }
            // The avatar is gone while profiles are off. See `ProfilesFeature`.
            if ProfilesFeature.isEnabled {
                Button { showingProfiles = true } label: {
                    ProfileAvatarImage(token: session.activeProfiles?.activeProfile?.avatar ?? "",
                                       diameter: 40,
                                       colorTag: session.activeProfiles?.activeProfile?.colorTag
                                           ?? Theme.Palette.defaultColorTag)
                        .padding(2)
                        .seretGlass(in: Circle())
                }
                .buttonStyle(GlassPressStyle())
                .accessibilityLabel("Switch profile")
            }
        }
        .animation(Theme.Motion.fade, value: pastHero)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if let home = homeStore {
            let picks = watchlistRows
            if !hasContent(home, picks: picks) {
                // A failed library said "Nothing here yet — play something" for good, and a library
                // with titles Home had not composed yet said it for the whole first build.
                if case .failed(let message) = session.libraryStore?.state {
                    failed(message)
                } else if stillLoading(home, picks: picks) {
                    loading
                } else if picks?.isRefreshing == true {
                    choosingPicks
                } else {
                    empty
                }
            } else {
                page(home, picks: picks)
            }
        } else {
            loading
        }
    }

    /// Anything to show — a download under way counts: a first title being fetched into an empty
    /// library is exactly when the viewer wants to see it. The watchlist rows stand in for
    /// Recently Added whenever Letterboxd is set up.
    private func hasContent(_ home: HomeStore, picks: HomeWatchlistRows?) -> Bool {
        if !home.continueWatching.isEmpty || !activeDownloads.isEmpty { return true }
        if let picks { return !picks.isEmpty }
        return !home.recentlyAdded.isEmpty
    }

    /// Nothing on Home YET: the library is still being read, or it has titles Home has not
    /// composed yet — or, with the watchlist rows in Recently Added's place, the picks have not
    /// answered once. Then it says it is empty rather than spinning for good.
    private func stillLoading(_ home: HomeStore, picks: HomeWatchlistRows?) -> Bool {
        guard let library = session.libraryStore else { return false }
        if library.state == .loading { return true }
        let libraryEmpty = library.movies.isEmpty && library.shows.isEmpty
        guard picks != nil else { return !libraryEmpty }
        return !picksLoaded || (!libraryEmpty && !home.hasBuiltForProfile)
    }

    private func heroSubject(_ home: HomeStore, picks: HomeWatchlistRows?) -> HomeHeroSubject? {
        if let first = home.continueWatching.first { return .resume(first) }
        if let picks {
            if let film = pickedFilm(in: picks.picked, row: .picked) { return .picked(film) }
            return pickedFilm(in: picks.both, row: .both).map(HomeHeroSubject.picked)
        }
        if let newest = home.recentlyAdded.first { return .added(newest) }
        return nil
    }

    /// The first film of a watchlist row that has a title page to open (one TMDB could not match
    /// opens nothing, so it never heads the page). Its details are read here — so Home follows the
    /// details store, re-drawing the hero as its synopsis and plate land, only while a watchlist
    /// film IS the hero.
    private func pickedFilm(in entries: [WatchlistEntry], row kind: HomePickedFilm.Row) -> HomePickedFilm? {
        for entry in entries {
            guard let item = MediaItem.watchlistTitle(entry, library: session.libraryStore) else { continue }
            return HomePickedFilm(entry: entry, item: item,
                                  details: entry.tmdbID.flatMap { watchlistDetails?.details[$0] },
                                  row: kind)
        }
        return nil
    }

    private func heroHeight(_ size: CGSize) -> CGFloat {
        isRegular ? max(400, min(size.height * 0.56, 520)) : size.height * 0.64
    }

    private func page(_ home: HomeStore, picks: HomeWatchlistRows?) -> some View {
        let subject = heroSubject(home, picks: picks)
        return GeometryReader { geo in
            let heroHeight = heroHeight(geo.size)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let subject {
                        HomeHero(subject: subject, home: home, art: art, session: session,
                                 regular: isRegular, height: heroHeight,
                                 artHeight: geo.size.height * 0.92, leadingMargin: margin,
                                 actions: heroActions)
                            // A new featured title re-runs the hero (its art, its settle budget).
                            .id(subject.item.id)
                    }
                    rails(home, picks: picks, featured: subject)
                }
                // No hero (only downloads under way): the page starts below the header, never
                // under it and the status bar.
                .padding(.top, subject == nil ? (isRegular ? Theme.Space.xxl : 84) : 0)
                .padding(.bottom, Theme.Space.xxxl)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                let past = offset > heroHeight - 150
                if past != pastHero { pastHero = past }
                // The shell's art scrolls with the page (iPad).
                if isRegular {
                    scrollMemory.offset = offset
                    shellBackdrop?.offset = offset
                }
            }
#if DEBUG
            // `-uiPreview homescript` scrolls the page without a finger (the iPad simulator
            // cannot be driven by touch here).
            .modifier(HomeScriptScroller(target: preview?.homeScript?.scrollTo))
#endif
        }
        // Only a hero runs under the status bar and the header.
        .ignoresSafeArea(edges: subject == nil ? [] : .top)
    }

    @ViewBuilder private func rails(_ home: HomeStore, picks: HomeWatchlistRows?,
                                    featured: HomeHeroSubject?) -> some View {
        let width = PosterTileMetrics.width(hSize)
        // The hero IS the first entry — the rail starts with the one after it, as in the mockups.
        let continuing: [HomeItem] = {
            guard case .resume(let first) = featured else { return home.continueWatching }
            return home.continueWatching.filter { $0.id != first.id }
        }()
        if !continuing.isEmpty {
            PosterRail(title: "Continue Watching") {
                ForEach(continuing) { hi in
                    Button { resume(hi) } label: {
                        PosterTile(posterPath: hi.item.posterPath, title: hi.item.title, width: width,
                                   progress: hi.fraction, chip: hi.isUpNext ? "Next" : nil)
                    }
                    .pressable()
                    // The same long-press the Apple TV offers: the title's page (a tap resumes),
                    // and the marks that take it off the rail.
                    .contextMenu {
                        ContinueWatchingActions(entry: hi, home: home, session: session,
                                                openTitle: { router.detail = hi.item },
                                                play: { router.playback = PlaybackPresentation(request: $0) })
                    }
                }
            }
        }
        if !activeDownloads.isEmpty {
            PosterRail(title: "Downloading") {
                ForEach(activeDownloads) { tile in
                    Button {
                        openDownload(tile, library: session.libraryStore, router: router)
                    } label: {
                        DownloadingTile(tile: tile, width: width, showsTitle: false)
                    }
                    .pressable()
                }
            }
        }
        if let picks {
            // The hero IS the first film of its row — that row starts with the one after it, as
            // Continue Watching does (the other row keeps it). No See All: these rows are the day's
            // short list, and the whole watchlist is a page of its own.
            let hero: HomePickedFilm? = if case .picked(let film) = featured { film } else { nil }
            let heroPicked = hero?.row == .picked ? hero?.entry.slug : nil
            let heroBoth = hero?.row == .both ? hero?.entry.slug : nil
            watchlistRail("Picked for Right Now", entries: picks.picked.filter { $0.slug != heroPicked },
                          picks: picks, chips: true, width: width)
#if DEBUG
                .id(HomeRailID.picked)
#endif
            watchlistRail("Both of You Want to See", entries: picks.both.filter { $0.slug != heroBoth },
                          picks: picks, chips: false, width: width)
#if DEBUG
                .id(HomeRailID.both)
#endif
        } else {
            // No Letterboxd username: Recently Added stands in, so Home is never blank.
            recentRail("Recently Added Movies", items: home.recentlyAddedMovies, kind: .movie, width: width)
#if DEBUG
            recentRail("Recently Added Shows", items: home.recentlyAddedShows, kind: .show, width: width)
                .id(HomeRailID.shows)
#else
            recentRail("Recently Added Shows", items: home.recentlyAddedShows, kind: .show, width: width)
#endif
        }
    }

    /// A watchlist row: each film's poster, whose list it is on ("Both", "Noga") when `chips` —
    /// not in Both of You Want to See, where every film would wear the same one — the grey ✓ when
    /// it is in the library and the white ✓ once watched. A tap opens its title page.
    @ViewBuilder private func watchlistRail(_ title: String, entries: [WatchlistEntry],
                                            picks: HomeWatchlistRows, chips: Bool,
                                            width: CGFloat) -> some View {
        if !entries.isEmpty {
            PosterRail(title: title) {
                ForEach(entries) { entry in
                    WatchlistFilmTile(entry: entry, owned: isOwned(entry),
                                      badge: chips ? WatchlistRows.badge(for: entry,
                                                                         membership: picks.membership,
                                                                         partnerName: picks.partnerName)
                                                   : nil,
                                      width: width, onRemove: { _ in }, allowsRemove: false)
                }
            }
            // One batched watched read per rail, as on the Watchlist page.
            .task(id: entries.map(\.slug)) { await marks?.load(WatchlistFilmMarks.hits(entries)) }
        }
    }

    private func isOwned(_ entry: WatchlistEntry) -> Bool {
        guard let id = entry.tmdbID else { return false }
        return session.libraryStore?.ownedItem(tmdbID: id, kind: .movie) != nil
    }

    /// The TMDB ids of the films on Home's rows, with whether the details store is there yet — so
    /// the fetch re-runs once it is, and whenever the rows change.
    private var watchlistDetailIDs: WatchlistDetailIDs {
        let picks = watchlistRows
        let ids = ((picks?.picked ?? []) + (picks?.both ?? [])).compactMap(\.tmdbID)
        return WatchlistDetailIDs(ids: ids, hasStore: watchlistDetails != nil)
    }

    private struct WatchlistDetailIDs: Equatable {
        let ids: [Int]
        let hasStore: Bool
    }

    @ViewBuilder private func recentRail(_ title: String, items: [MediaItem], kind: MediaKind,
                                         width: CGFloat) -> some View {
        if !items.isEmpty {
            // "See All" only once there is more than a screenful to see.
            PosterRail(title: title, seeAll: items.count > 6 ? HomeRoute.recentlyAdded(kind) : nil) {
                ForEach(items) { item in
                    Button { router.detail = item } label: {
                        PosterTile(posterPath: item.posterPath, title: item.title, width: width,
                                   watched: session.libraryStore?.watchState(for: item)?.finished == true)
                    }
                    .pressable()
                    .libraryTitleMenu(for: item, session: session, onRemove: { pendingRemoval = $0 })
                }
            }
        }
    }

    private var heroActions: HomeHeroActions {
        let router = router
        return HomeHeroActions(resume: { resume($0) },
                               open: { router.detail = $0 },
                               play: { router.playback = PlaybackPresentation(request: $0) },
                               remove: { pendingRemoval = $0 })
    }

    /// Resume playback straight from Home. Falls back to the title's page only if the file can't
    /// be resolved (e.g. the version was removed since it was last watched).
    private func resume(_ hi: HomeItem) {
        if let request = hi.playbackRequest() {
            router.playback = PlaybackPresentation(request: request)
        } else {
            router.detail = hi.item
        }
    }

    // MARK: States

    private var loading: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 28) {
                ShimmerView()
                    .frame(height: heroHeight(geo.size))
                    .mask(LinearGradient(colors: [.black, .black.opacity(0)],
                                         startPoint: .center, endPoint: .bottom))
                RailSkeleton(rows: 1)
            }
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 40))
                .foregroundStyle(Theme.Palette.textSecondary)
            Text(message).font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, Theme.Space.lg)
            Button { session.libraryStore?.reload() } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PrimaryPillButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The day's first list is still being made (a minute of Letterboxd pages on a first run) and
    /// nothing else is on Home. "Nothing here yet — play something" read as broken over a library
    /// full of titles.
    private var choosingPicks: some View {
        VStack(spacing: Theme.Space.md) {
            SeretMark(glow: false).frame(width: 54).opacity(0.5)
            Text("Choosing films for tonight").font(Theme.Typo.headline())
                .foregroundStyle(Theme.Palette.textSecondary)
            Text("Reading your Letterboxd watchlists. The first time takes a minute.")
                .font(Theme.Typo.body())
                .foregroundStyle(Theme.Palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var empty: some View {
        VStack(spacing: Theme.Space.md) {
            SeretMark(glow: false).frame(width: 54).opacity(0.5)
            Text("Nothing here yet").font(Theme.Typo.headline()).foregroundStyle(Theme.Palette.textSecondary)
            Text("Play something and it'll show up here.").font(Theme.Typo.body())
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rebuild() async {
        guard session.libraryStore != nil, let home = session.home else { return }
        // Continue Watching, and the watchlist rows with it: a film finished in the player leaves
        // them, a Letterboxd username set in Settings since is picked up, and a new day's picks are
        // computed in the background.
        await session.refreshHome()
        // Warm the first screenful of each rail in the background so tiles render filled instead
        // of popping in one by one as they scroll into view.
        var urls = home.continueWatching.prefix(8).compactMap { posterURL($0.item) }
        if let picks = session.homePicks {
            urls += (picks.picked.prefix(8) + picks.both.prefix(8)).compactMap {
                TMDBClient.imageURL(path: $0.posterPath, size: "w342")
            }
        } else {
            urls += home.recentlyAddedMovies.prefix(8).compactMap { posterURL($0) }
            urls += home.recentlyAddedShows.prefix(8).compactMap { posterURL($0) }
        }
        ImageMemoryCache.prefetch(urls)
    }

    private func posterURL(_ i: MediaItem) -> URL? { TMDBClient.imageURL(path: i.posterPath, size: "w342") }
}

/// Home's last scroll offset — a reference, so writing it per scroll frame invalidates nothing.
private final class ScrollMemory {
    var offset: CGFloat = 0
}

#if DEBUG
/// Scroll targets on Home's page (`-uiPreview homescript` only).
enum HomeRailID {
    static let shows = "home-rail-shows"
    static let picked = "home-rail-picked"
    static let both = "home-rail-both"
}

/// `-uiPreview homescript`: scrolls the page to a rail without a finger. Wraps the scroll view in
/// the reader only in DEBUG, so Release carries no harness plumbing.
private struct HomeScriptScroller: ViewModifier {
    let target: String?

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.onChange(of: target) { _, target in
                if let target { withAnimation { proxy.scrollTo(target, anchor: .top) } }
            }
        }
    }
}
#endif

/// Where Home's "See All" links go.
enum HomeRoute: Hashable {
    case recentlyAdded(MediaKind)
}

/// Every recently added movie (or show) Home holds, as a grid — Recently Added's "See All".
struct RecentlyAddedGrid: View {
    let kind: MediaKind
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var pendingRemoval: MediaItem?
    @State private var removeErrorMessage: String?
#if DEBUG
    @Environment(\.uiPreviewStores) private var preview
    private var homeStore: HomeStore? { preview?.home ?? session.home }
#else
    private var homeStore: HomeStore? { session.home }
#endif

    private var items: [MediaItem] {
        kind == .movie ? homeStore?.recentlyAddedMovies ?? [] : homeStore?.recentlyAddedShows ?? []
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            ScrollView {
                LazyVGrid(columns: PosterTileMetrics.gridColumns(hSize), spacing: PosterTileMetrics.spacing + 4) {
                    ForEach(items) { item in
                        Button { router.detail = item } label: {
                            PosterTile(posterPath: item.posterPath, title: item.title, width: nil,
                                       watched: session.libraryStore?.watchState(for: item)?.finished == true)
                        }
                        .pressable()
                        .libraryTitleMenu(for: item, session: session, onRemove: { pendingRemoval = $0 })
                    }
                }
                .padding(.horizontal, PosterTileMetrics.margin(hSize))
                .padding(.bottom, Theme.Space.xxxl)
            }
        }
        .navigationTitle(kind == .movie ? "Recently Added Movies" : "Recently Added Shows")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .libraryRemovalConfirmation(pending: $pendingRemoval,
                                    errorMessage: $removeErrorMessage,
                                    store: session.libraryStore)
    }
}
