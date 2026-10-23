import DebridCore
import DebridUI
import SwiftUI

/// The signed-in root: a Plex-style floating side menu over the switched content. The menu is an
/// overlay — content is inset by the collapsed capsule's footprint and never moves when the menu
/// opens. One root NavigationStack OUTSIDE the content so Detail / the player still cover
/// everything cleanly.
struct LibraryShell: View {
    @Environment(AppSession.self) private var session
    @State private var tab: SideMenuItem = .home
    /// The page being switched away from, kept drawn while it fades out — see `ShellPages`.
    @State private var leavingTab: SideMenuItem?
    /// Removal requested by a poster anywhere under the shell — see `requestLibraryRemoval`.
    @State private var pendingRemoval: MediaItem?
    @State private var removeErrorMessage: String?
    /// The shell's actions and the menu-focus flag, handed down as stable objects — see `ShellAction`.
    @State private var openAction = ShellAction<BrowseDestination>()
    @State private var removalAction = ShellAction<MediaItem>()
    @State private var menuFlag = SideMenuFocusFlag()
    @State private var path = NavigationPath()
    @State private var showingProfiles = false
    @FocusState private var menuFocus: SideMenuItem?
    /// Watched marks for every browse/search poster. Held here so all the grids share one cache and
    /// switching pages does not re-query what is already known.
    @State private var tileMarks: TileWatchMarks?
    /// The watchlist toggle every tile and title page offers. Built here so one object serves the
    /// whole shell, and read OPTIONALLY everywhere — see the comment in `BrowseTile`.
    @State private var watchlistMarks: WatchlistMarks?


    /// Whether the panel is widened.
    ///
    /// Deliberately NOT derived from `menuFocus`. tvOS parks focus on this rail unprompted (it is
    /// the top-leading view) and will not hand focus back to the page afterwards — `@FocusState`
    /// writes, `resetFocus(in:)` + `prefersDefaultFocus`, and disabling the menu were all tried and
    /// ignored. So focus-presence would mean the menu sat open at launch and stayed open over the
    /// page you just picked.
    ///
    /// The signal that works is a *user action*, not a focus event: `.onMoveCommand` fires only
    /// when someone actually presses a direction, which tvOS's own focus bookkeeping never does.
    /// Gated on `menuFocus != nil` because that command also arrives from the profile picker on the
    /// way in. Collapsing is not a move command, so nothing re-opens the menu behind your back.
    @State private var menuExpanded = false
    /// The page has held focus at least once. Distinguishes a real navigation INTO the menu from
    /// tvOS parking focus on the rail at launch — see the `menuFocus` change handler.
    @State private var pageHasHeldFocus = false
    /// Whether the side menu is on screen yet. False only for the first moments after launch — see
    /// `revealMenuAfterLaunchFocus()`.
    @State private var menuRevealed = false
    private var menuOpen: Bool { menuExpanded }

    /// Search needs a kind and the menu has none — take the section the user is browsing.
    private var searchKind: MediaKind { tab == .shows ? .show : .movie }

    #if DEBUG
    /// Whether `-openTitle` has already pushed its page, so a later library refresh does not
    /// push it again.
    @State private var openedTitleForTesting = false
    @State private var autoPlayedForTesting = false

    /// DEBUG-only: `-openTitle <text>` pushes the title page of the first library film (or, failing
    /// that, show) whose title contains the text. It checks a title page against the real account without walking the focus
    /// engine, which takes synthesized keystrokes unreliably.
    ///
    ///     xcrun simctl launch <udid> com.solomons.seret.tv -openTitle Arrival
    ///
    /// `-openVersions <text>` pushes that film's full-screen Versions list instead: the real
    /// search, ranking and Hebrew evidence, without walking to "Find Other Versions".
    private func openTitleForTesting() {
        let args = ProcessInfo.processInfo.arguments
        let flag = args.contains("-openVersions") ? "-openVersions" : "-openTitle"
        guard !openedTitleForTesting, let i = args.firstIndex(of: flag), i + 1 < args.count,
              let store = session.libraryStore, !store.movies.isEmpty else { return }
        let needle = args[i + 1].lowercased()
        // Shows too, so a season/episode page can be checked the same way. Versions stays
        // film-only: it builds a movie search hit below.
        let candidates = flag == "-openVersions" ? store.movies : store.movies + store.shows
        guard let item = candidates.first(where: { $0.title.lowercased().contains(needle) }) else { return }
        openedTitleForTesting = true
        guard flag == "-openVersions" else { path.append(item); return }
        guard let tmdb = item.tmdbID else { return }
        path.append(BrowseDestination.versions(SearchHit(result: TMDBSearchResult(
            id: tmdb, title: item.title, name: nil, releaseDate: nil, firstAirDate: nil,
            posterPath: item.posterPath, overview: nil, voteAverage: nil), kind: .movie)))
    }

    /// DEBUG-only: `-autoPlay…` pushes the player the way every real play path does. See
    /// `AutoPlayHarness` for the flags, and for why this is a push and not a cover.
    private func autoPlayForTesting() {
        guard !autoPlayedForTesting, !AutoPlayHarness.runsMemoryTimeline,
              let index = AutoPlayHarness.launchIndex, let store = session.libraryStore,
              let request = AutoPlayHarness.request(in: store, index: index) else { return }
        autoPlayedForTesting = true
        path.append(BrowseDestination.play(request))
    }
    #endif

    var body: some View {
        // The shell's actions forward to its current state. Plain assignments into objects nothing
        // observes, so running them re-renders nothing.
        let pathBinding = $path, removal = $pendingRemoval
        let _ = openAction.set { pathBinding.wrappedValue.append($0) }
        let _ = removalAction.set { removal.wrappedValue = $0 }
        ZStack(alignment: .leading) {
            NavigationStack(path: $path) {
                pages
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Content clears the collapsed capsule. This sits on the ROOT content only —
                    // pushed destinations are separate views and stay full-bleed.
                    .sideMenuContentInset()
                    .environment(\.sideMenuFocus, menuFlag)
                    .navigationDestination(for: BrowseDestination.self) { dest in
                        switch dest {
                        case .detail(let item): detailDestination(item)
                        case .search(let kind): SearchScreen(kind: kind)
                        case .versions(let hit): VersionsScreen(hit: hit)
                        case .episodeVersions(let hit, let season, let number):
                            VersionsScreen(hit: hit, episode: (season: season, number: number))
                        case .person(let ref): PersonScreen(ref: ref)
                        case .genre(let kind, let genre, let seed):
                            GenreGridScreen(kind: kind, genre: genre, seed: seed)
                        case .play(let request):
                            PlayerHost(request: request, app: session, backdropSize: "original")
                        }
                    }
                    .navigationDestination(for: SearchHit.self) { hit in
                        detailDestination(.placeholder(for: hit))
                    }
                    .navigationDestination(for: MediaItem.self) { item in
                        detailDestination(item)
                    }
                    .navigationDestination(for: PlaybackRequest.self) { request in
                        PlayerHost(request: request, app: session, backdropSize: "original")
                    }
            }
            // The menu hides while a Detail/Player is pushed so those stay full-screen.
            if path.isEmpty && menuRevealed {
                SideMenuScrim(visible: menuOpen)
                SideMenu(selected: tab,
                         profileName: session.activeProfiles?.activeProfile?.name ?? "Profile",
                         profileAvatar: session.activeProfiles?.activeProfile?.avatar ?? "",
                         profileColorTag: session.activeProfiles?.activeProfile?.colorTag ?? Theme.Palette.defaultColorTag,
                         focus: $menuFocus,
                         expanded: menuExpanded,
                         onSelect: select,
                         onProfile: { showingProfiles = true })
                // A directional press WHILE the menu holds focus = the user is navigating it, so
                // widen. Both halves matter: a move command alone also arrives from the profile
                // picker on the way in (which would open the menu at launch), and focus alone is
                // what tvOS hands the rail unprompted.
                .onMoveCommand { _ in if menuFocus != nil { menuExpanded = true } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanvasBackground())
        // Both actions are set out HERE, around the whole stack, so a PUSHED page sees them too.
        // They used to sit on the root pages, below the `navigationDestination` that builds every
        // pushed page — so a person's credits, "More Like This" and Search all got the do-nothing
        // default: Remove on a poster there silently did nothing, and a pushed page could not open
        // the player as a push. The confirmation moves with them, so its alert presents over
        // whichever page is on top rather than from a root page that is not on screen.
        .environment(\.requestLibraryRemoval, removalAction)
        .environment(\.openBrowseDestination, openAction)
        .libraryRemovalConfirmation(pending: $pendingRemoval,
                                    errorMessage: $removeErrorMessage,
                                    store: session.libraryStore)
        // Menu button opens the nav from anywhere; a second press falls through and exits, because
        // the handler is removed while the menu is already open.
        .onExitCommand(perform: menuOpen || !path.isEmpty ? nil : {
            menuRevealed = true
            menuFocus = tab
            menuExpanded = true
        })
        // Focus ENTERING the menu opens it; focus leaving collapses it.
        //
        // The entry half is what fixes "I have to swipe left twice". `.onMoveCommand` above only
        // fires while the menu ALREADY holds focus, so the first press from a page — the one the
        // focus engine spends moving focus into the rail — was invisible to it, and the menu stayed
        // a collapsed strip with a focused row inside it until you pressed again.
        //
        // `pageHasHeldFocus` is what keeps this from re-creating the bug it replaced: tvOS parks
        // focus on this rail unprompted at launch (it is the top-leading view), and expanding on
        // that would open the menu over the page before the viewer touched anything. A focus entry
        // only counts once the PAGE has held focus, which can only happen after a real navigation.
        .onChange(of: menuFocus) { _, new in
            menuFlag.holdsFocus = new != nil
            if new == nil {
                pageHasHeldFocus = true
                menuExpanded = false
            } else if pageHasHeldFocus {
                menuExpanded = true
            }
        }
        .task(id: session.libraryStore?.attempt ?? -1) {
            await session.libraryStore?.load()
        }
        .task { await revealMenuAfterLaunchFocus() }
        #if DEBUG
        .task(id: "\(session.libraryStore?.movies.count ?? 0)-\(session.libraryStore?.shows.count ?? 0)") {
            openTitleForTesting()
            autoPlayForTesting()
            QAScriptRunner.shared.runIfRequested(
                store: session.libraryStore,
                push: { path.append(BrowseDestination.play($0)) },
                popToRoot: { path = NavigationPath() },
                selectTab: { switchTab(to: $0) })
        }
        .onAppear { QA.startMeters() }
        #endif
        .task { if tileMarks == nil { tileMarks = session.makeTileWatchMarks() } }
        .environment(tileMarks ?? .placeholder)
        .task {
            if watchlistMarks == nil { watchlistMarks = session.makeWatchlistMarks() }
            await watchlistMarks?.load()
        }
        .environment(watchlistMarks ?? .placeholder)
        .task(id: tab) {
            // Cancelled by the next switch: that switch has already named its own leaving page.
            guard (try? await Task.sleep(for: ShellPages.leavingHold)) != nil else { return }
            leavingTab = nil
        }
        .onChange(of: tab) { _, new in
            if new == .home { Task { await session.refreshHome() } }
            // A page the viewer comes back to should not show a library from hours ago.
            session.libraryStore?.refreshIfStale(maxAge: RootView.libraryMaxAge)
        }
        .onChange(of: path.isEmpty) { _, empty in if empty { Task { await session.refreshHome() } } }
        .fullScreenCover(isPresented: $showingProfiles) {
            WhoIsWatchingScreen(onPicked: { showingProfiles = false }).environment(session)
        }
    }

    /// Puts the side menu on screen once the page has had its chance at the launch focus.
    ///
    /// tvOS gives initial focus to the top-leading focusable on screen, and the menu's first row
    /// always won it: the app opened with Search focused — one click from the keyboard — and Home's
    /// Resume a press away. A view that is not in the hierarchy cannot win, so the menu waits until
    /// Home has something focusable on screen, or ~2.5s at most (an empty Home has nothing to focus,
    /// and the menu must not stay away). The splash covers this window.
    ///
    /// Revealing the menu cannot take focus FROM the page — tvOS parks it on the rail only when
    /// nothing else holds it — so the rail not holding focus a moment later means the page does.
    /// That is the `pageHasHeldFocus` fact the expansion logic needs, which it otherwise learns only
    /// when focus first LEAVES the rail; without it the first LEFT into the menu would leave the
    /// panel collapsed (the old "swipe left twice").
    private func revealMenuAfterLaunchFocus() async {
        guard !menuRevealed else { return }
        for _ in 0..<25 {
            if tab != .home || homeSettledForLaunchFocus { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(250))   // let the focus engine settle on the page
        menuRevealed = true
        try? await Task.sleep(for: .milliseconds(300))
        if menuFocus == nil { pageHasHeldFocus = true }
    }

    /// Home has drawn the tile it will open on: the first Continue Watching tile, or — with no
    /// Continue Watching — the first Recently Added one, but only once that is an answer for the
    /// profile. Recently Added arrives first (it needs no profile), and revealing on it parked
    /// focus on a poster whose rail Continue Watching then pushed off the top of the screen.
    private var homeSettledForLaunchFocus: Bool {
        guard let home = session.home else { return false }
        if !home.continueWatching.isEmpty { return true }
        return home.hasBuiltForProfile && !home.recentlyAdded.isEmpty
    }

    /// Search pushes, the profile presents, everything else switches the page. Commit-on-press —
    /// focusing a row only highlights it, so gliding the remote never rebuilds a page.
    private func select(_ item: SideMenuItem) {
        switch item {
        case .search:  path.append(BrowseDestination.search(searchKind))
        case .profile: showingProfiles = true
        default:
            switchTab(to: item)
            menuExpanded = false   // collapse onto the page you just chose
        }
    }

    /// Names the page being left in the same transaction as the switch, so it is never hollowed for
    /// a frame before its fade starts.
    private func switchTab(to item: SideMenuItem) {
        guard item != tab else { return }
        leavingTab = tab
        tab = item
    }

    /// The library Detail for a pushed item (shared by the MediaItem and BrowseDestination routes).
    @ViewBuilder private func detailDestination(_ item: MediaItem) -> some View {
        if let details = session.detailsProvider {
            DetailView(item: item, details: details, watch: session.watchStore,
                       profileID: session.activeProfileID,
                       myList: session.myListStore,
                       ratings: session.ratingsProvider,
                       versionPrefs: session.versionPreferences,
                       letterboxd: session.letterboxdRatingProvider,
                       subtitleEvidence: session.subtitleEvidence)
        }
    }

    /// The root pages — see `ShellPages`.
    private var pages: some View {
        ShellPages(tab: tab, leaving: leavingTab).equatable()
    }
}


/// The root pages. Pages stay alive across switches (instant, no rebuild → snappy). Movies/Shows
/// are separate browse surfaces, so each keeps its own rows, scroll and focus. The whole area is
/// one focus section so travel between the menu and a page is unambiguous.
///
/// Its own `Equatable` view, compared on `tab` alone: the shell's body runs on every press in the
/// side menu (it follows the menu's focus), and every run re-created these pages — which SwiftUI
/// cannot compare, so Home and the Watchlist re-ran their whole bodies on each press (measured
/// with `_printChanges`: "@self changed", twice per press). Everything else they need arrives
/// through the environment, which still reaches them.
///
/// Switching is a fade-through, not a cut: the page left fades out quickly, and the page chosen
/// fades in a beat later from a hair smaller. The page left stays drawn (`leaving`) until its fade
/// is over — hollowing it at once would blank it on the first frame of the switch.
private struct ShellPages: View, Equatable {
    let tab: SideMenuItem
    let leaving: SideMenuItem?

    static let fadeOut = Animation.easeIn(duration: 0.16)
    static let fadeIn = Animation.easeOut(duration: 0.3).delay(0.08)
    /// How long the page left stays drawn: past the end of its fade-out.
    static let leavingHold = Duration.milliseconds(250)

    var body: some View {
        ZStack {
            keptAlive(.home) { HomeScreen() }
            keptAlive(.movies) { BrowseScreen(kind: .movie) }
            keptAlive(.shows) { BrowseScreen(kind: .show) }
            keptAlive(.watchlist) { WatchlistScreen() }
            keptAlive(.library) { MyLibraryScreen() }
            if tab == .settings {
                SettingsView().transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.985)).animation(Self.fadeIn),
                    removal: .opacity.animation(Self.fadeOut)))
            }
        }
        .focusSection()
    }

    @ViewBuilder private func keptAlive<V: View>(_ page: SideMenuItem, @ViewBuilder _ make: () -> V) -> some View {
        let visible = tab == page
        let drawn = visible || leaving == page
        make()
            // A transparent page still holds every bitmap it drew; this lets its images go (the
            // cache keeps the recent ones, so coming back is still instant).
            .environment(\.retainsImages, drawn)
            // Hidden pages keep their state but drop their tiles — see `ShellPageVisibleKey`.
            .environment(\.shellPageVisible, drawn)
            // Scoped to these two modifiers, so nothing the switch changes INSIDE the page animates.
            .animation(visible ? Self.fadeIn : Self.fadeOut) {
                $0.opacity(visible ? 1 : 0).scaleEffect(visible ? 1 : 0.985)
            }
            .allowsHitTesting(visible)
            .disabled(!visible)
            .accessibilityHidden(!visible)
    }
}

/// How a view under the shell opens a page without owning its `NavigationPath` — a long-press menu
/// item cannot be a `NavigationLink`. The shell sets it; the default does nothing, for the reason
/// `requestLibraryRemoval` has one: a missing closure must be a no-op, never a trap.
private struct OpenBrowseDestinationKey: EnvironmentKey {
    static let defaultValue = ShellAction<BrowseDestination>()
}

/// Whether the side menu holds focus. A page that moves focus by itself (Home handing focus on
/// from a removed tile) must never pull it back out of the menu. A stable flag, read when acting —
/// see `SideMenuFocusFlag`.
private struct SideMenuFocusKey: EnvironmentKey {
    static let defaultValue = SideMenuFocusFlag()
}

/// Whether this root page is the one on screen. A kept-alive page behind another keeps its state
/// (its models, loads and focus memory) but builds NO tiles, header or backdrop while hidden.
///
/// Measured on the real Apple TV with a scripted walk along Home's rail: with Movies, Shows,
/// Watchlist and Library alive behind Home, every focus move dropped 0.6–1.4 frames; with them gone,
/// 0.03–0.05. No one page was the cause — dropping any single one changed nothing — the cost grows
/// with every focusable tile in the window, visible or not. Pushed pages never set it (default true).
private struct ShellPageVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// A `ShellAction`, not a closure — see why there.
    var openBrowseDestination: ShellAction<BrowseDestination> {
        get { self[OpenBrowseDestinationKey.self] }
        set { self[OpenBrowseDestinationKey.self] = newValue }
    }

    var shellPageVisible: Bool {
        get { self[ShellPageVisibleKey.self] }
        set { self[ShellPageVisibleKey.self] = newValue }
    }

    var sideMenuFocus: SideMenuFocusFlag {
        get { self[SideMenuFocusKey.self] }
        set { self[SideMenuFocusKey.self] = newValue }
    }
}
