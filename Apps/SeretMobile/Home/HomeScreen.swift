import DebridCore
import DebridUI
import SwiftUI

/// Home, as the mockups (g1 iPhone, m5 iPad) and the Apple TV draw it: a full-bleed hero for the
/// title you were last watching, then sideways poster rails — Continue Watching, Downloading
/// (while anything is), Recently Added Movies, Recently Added Shows — composed on `session.home`.
///
/// - iPhone: the art runs under the status bar and the glass header ("Seret", Search, Settings);
///   the header's shade only firms up once the hero has scrolled away.
/// - iPad: the art runs the page's width and on under the floating sidebar
///   (`shellLeadingInset`), with the preview (logo, metadata, synopsis, buttons) on the left.
///
/// Resume plays directly (the title's page only when its file no longer resolves); a tile in
/// Continue Watching resumes too and keeps its long-press marks; Recently Added tiles open the
/// title's page and keep the library menu; Downloading tiles open the page of what is landing.
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

#if DEBUG
    /// Fixture stores from a `-uiPreview` harness (see `PagesUIPreview`), else the session's.
    @Environment(\.uiPreviewStores) private var preview
    private var homeStore: HomeStore? { preview?.home ?? session.home }
    private var art: TitleArtStore? { preview?.art ?? session.titleArt }
    private var activeDownloads: [DownloadTile] {
        preview?.downloads ?? session.downloadStore?.activeTiles ?? []
    }
#else
    private var homeStore: HomeStore? { session.home }
    private var art: TitleArtStore? { session.titleArt }
    private var activeDownloads: [DownloadTile] { session.downloadStore?.activeTiles ?? [] }
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
        .onChange(of: session.libraryStore?.movies) { _, _ in Task { await rebuild() } }
        .onChange(of: session.libraryStore?.shows) { _, _ in Task { await rebuild() } }
        // The active profile resolves asynchronously after sign-in; rebuild once it's known.
        .onChange(of: session.activeProfileID) { _, _ in Task { await rebuild() } }
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
        let overArt = homeStore.map { heroSubject($0) != nil } ?? false
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
            if home.continueWatching.isEmpty && home.recentlyAdded.isEmpty && activeDownloads.isEmpty {
                // A failed library said "Nothing here yet — play something" for good, and a library
                // with titles Home had not composed yet said it for the whole first build.
                if case .failed(let message) = session.libraryStore?.state {
                    failed(message)
                } else if let library = session.libraryStore,
                          library.state == .loading || !(library.movies.isEmpty && library.shows.isEmpty) {
                    loading
                } else {
                    empty
                }
            } else {
                page(home)
            }
        } else {
            loading
        }
    }

    private func heroSubject(_ home: HomeStore) -> HomeHeroSubject? {
        if let first = home.continueWatching.first { return .resume(first) }
        if let newest = home.recentlyAdded.first { return .added(newest) }
        return nil
    }

    private func heroHeight(_ size: CGSize) -> CGFloat {
        isRegular ? max(400, min(size.height * 0.56, 520)) : size.height * 0.64
    }

    private func page(_ home: HomeStore) -> some View {
        GeometryReader { geo in
            let subject = heroSubject(home)
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
                    rails(home, featured: subject)
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
        .ignoresSafeArea(edges: heroSubject(home) == nil ? [] : .top)
    }

    @ViewBuilder private func rails(_ home: HomeStore, featured: HomeHeroSubject?) -> some View {
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
        recentRail("Recently Added Movies", items: home.recentlyAddedMovies, kind: .movie, width: width)
#if DEBUG
        recentRail("Recently Added Shows", items: home.recentlyAddedShows, kind: .show, width: width)
            .id(HomeRailID.shows)
#else
        recentRail("Recently Added Shows", items: home.recentlyAddedShows, kind: .show, width: width)
#endif
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
        guard let library = session.libraryStore, let home = session.home else { return }
        await home.rebuild(movies: library.movies, shows: library.shows)
        // Warm the first screenful of each rail in the background so tiles render filled instead
        // of popping in one by one as they scroll into view.
        var urls = home.continueWatching.prefix(8).compactMap { posterURL($0.item) }
        urls += home.recentlyAddedMovies.prefix(8).compactMap { posterURL($0) }
        urls += home.recentlyAddedShows.prefix(8).compactMap { posterURL($0) }
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
