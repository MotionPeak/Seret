import DebridCore
import DebridUI
import SwiftUI

/// Home tab, Plex-style: a focus-driven preview header (logo, metadata, synopsis over the ultrablur
/// backdrop of the focused title) above sideways poster rails — Continue Watching, Downloading
/// (while anything is), then "Picked for Right Now" and "Both of You Want to See" from the
/// Letterboxd watchlists (`session.homePicks`) — composed on the shared `session.home`. With no
/// Letterboxd username set up, Recently Added Movies and Recently Added Shows take the watchlist
/// rows' place, so Home is never blank.
///
/// Continue Watching resumes on Select (its page only when the file no longer resolves) and keeps
/// its press-and-hold menu; Recently Added tiles open the title's page and keep the library menu and
/// the watched ✓; Downloading tiles and watchlist films open the title's page. A watchlist film has
/// no long-press Remove here — the Watchlist page owns removal.
struct HomeScreen: View {
    @Environment(AppSession.self) private var session
    /// Pushes a page onto the shell's stack. A no-op outside the shell (previews, the harness).
    @Environment(\.openBrowseDestination) private var openDestination
    /// Whether the side menu holds focus — Home must not move focus by itself then (see
    /// `rehomeFocus`). Read when acting, never in the body.
    @Environment(\.sideMenuFocus) var sideMenuFocus
    /// False while Home is a kept-alive page behind another one (the shell disables it).
    @Environment(\.isEnabled) var isVisiblePage

    /// A title awaiting removal confirmation, and the failure to surface if RD refuses. Home hosts
    /// these itself because a rail is a place you remove from, not only a place you browse.
    @State private var pendingRemoval: MediaItem?
    @State private var removeErrorMessage: String?

#if DEBUG
    /// The store the `-uiPreview home` harness renders instead of the session's, so the real screen
    /// — header and every rail together — can be screenshot-verified without a signed-in session and
    /// without a watch history the simulator has no cheap way to produce.
    var previewHome: HomeStore?
    private var homeStore: HomeStore? { previewHome ?? session.home }
    /// The harness's art store (the unsigned preview session has none), so the header and backdrop
    /// are measured with real logos and plates.
    var previewArt: TitleArtStore?
    private var art: TitleArtStore? { previewArt ?? session.titleArt }
    /// The harness's library failure (`-uiPreview homefailed`) — the preview session has no library.
    var previewFailure: String?
    /// The harness's downloads (`-uiPreview homedownloading`) — the preview session has no store.
    var previewDownloads: [DownloadTile]?
    var activeDownloads: [DownloadTile] { previewDownloads ?? session.downloadStore?.activeTiles ?? [] }
    /// The harness's watchlist rows (`-uiPreview homepicks`) — the preview session has no
    /// Letterboxd account.
    var previewPicks: HomeWatchlistRows?
    /// The harness's watchlist details, so a picked film's header has its synopsis and backdrop.
    var previewWatchlistDetails: WatchlistDetailsStore?
    var watchlistRows: HomeWatchlistRows? {
        previewPicks ?? session.homePicks.map(HomeWatchlistRows.init)
    }
    private var injectedWatchlistDetails: WatchlistDetailsStore? { previewWatchlistDetails }
#else
    private var homeStore: HomeStore? { session.home }
    private var art: TitleArtStore? { session.titleArt }
    var activeDownloads: [DownloadTile] { session.downloadStore?.activeTiles ?? [] }
    /// Home's watchlist rows. Nil when no Letterboxd username is set — Home then shows Recently
    /// Added instead.
    var watchlistRows: HomeWatchlistRows? { session.homePicks.map(HomeWatchlistRows.init) }
    private var injectedWatchlistDetails: WatchlistDetailsStore? { nil }
#endif

    /// The watchlist films' TMDB details (synopsis, backdrop, logo) for their headers — the one the
    /// Watchlist page fills. Set once Home appears, never made in the body: making it registers it
    /// on the session.
    @State private var watchlistDetails: WatchlistDetailsStore?
    /// `HomePicksStore.load()` has answered once — until then "nothing on Home" is not yet known.
    @State private var picksLoaded = false

    /// Drives the preview header: tiles report focus, it publishes the one focus settles on.
    @State private var preview = FocusPreviewModel()
    /// Home's line to the page's focus: which tile holds it, and moving it. Not a `FocusState` of
    /// Home's own — that re-rendered Home, and rebuilt every rail, on each move along a rail.
    @State var focusHandle = FocusBrowseHandle()
    /// What every focus move writes. Not observed: nothing in it is drawn, so a move along a rail
    /// must not re-render Home for it.
    @State var focusMemory = HomeFocusMemory()
    /// The tile focus was on when it last left Home's tiles — where coming back into the page
    /// lands. Written once per departure, not per move, because the page's focus target reads it.
    @State var entryTile: String?

    /// True once there's anything to show — a download under way counts: a first title being fetched
    /// into an empty library is exactly when the viewer wants to see it.
    private var homeReady: Bool {
        guard let h = homeStore else { return false }
        if !activeDownloads.isEmpty || !h.continueWatching.isEmpty { return true }
        if let picks = watchlistRows { return !picks.isEmpty }
        return !h.recentlyAdded.isEmpty
    }

    /// A Try Again is under way — see `failed(_:)`.
    @State private var retrying = false
    @State private var lastFailure: String?

    /// What the failure screen says: the library's own failure, or — while a Try Again is under way
    /// and the library reads "loading" — the one being retried. ONE value feeding ONE branch: as two
    /// branches that both drew `failed(…)`, the flip from failed to loading swapped one for the
    /// other, the focused Try Again went with it, and tvOS put focus on the side menu.
    private var failureMessage: String? {
#if DEBUG
        if let previewFailure { return previewFailure }
#endif
        if case .failed(let message) = session.libraryStore?.state { return message }
        return retrying ? lastFailure : nil
    }

    /// Nothing on Home YET: the library is still being read, or it has titles that Home has not
    /// composed yet. Both used to show "Nothing here yet — play something", for the whole first
    /// build of a cold launch.
    ///
    /// With the watchlist rows in Recently Added's place, a library with titles in it no longer
    /// means Home has something to show — so it waits for Home's first build and the picks' first
    /// answer instead, then says it is empty rather than spinning for good.
    private var stillLoading: Bool {
        guard let library = session.libraryStore else { return false }
        if library.state == .loading { return true }
        let libraryEmpty = library.movies.isEmpty && library.shows.isEmpty
        guard watchlistRows != nil else { return !libraryEmpty }
        return !picksLoaded || (!libraryEmpty && homeStore?.hasBuiltForProfile != true)
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
        .task { await rebuild() }
        // The watchlist rows: the day's cached picks and the mirrors at once, the day's refresh in
        // the background (store-owned, so it outlives this task). Again when the Letterboxd
        // account changes, which replaces the store.
        .task(id: session.homePicks.map(ObjectIdentifier.init)) {
            if watchlistDetails == nil {
                watchlistDetails = injectedWatchlistDetails ?? session.makeWatchlistDetailsStore()
            }
            await session.homePicks?.load()
            picksLoaded = true
        }
        // The details of the films on Home's rows — the synopsis, backdrop and logo their headers
        // show. Fetched here rather than left to the Watchlist page's preload, which is gated and
        // walks the whole list. Again for a new day's list; the store skips what it already has.
        .task(id: watchlistDetailIDs) {
            guard !watchlistDetailIDs.ids.isEmpty else { return }
            await watchlistDetails?.ensure(watchlistDetailIDs.ids)
        }
        .onChange(of: session.libraryStore?.state) { _, state in
            if state != .loading { retrying = false }      // answered, either way
        }
        .onChange(of: session.libraryStore?.movies) { _, _ in Task { await rebuild() } }
        .onChange(of: session.libraryStore?.shows) { _, _ in Task { await rebuild() } }
        // The active profile resolves asynchronously after sign-in; rebuild once it's known so
        // Continue Watching isn't stuck on the empty (no-profile) state.
        .onChange(of: session.activeProfileID) { _, _ in Task { await rebuild() } }
        .libraryRemovalConfirmation(pending: $pendingRemoval,
                                    errorMessage: $removeErrorMessage,
                                    store: session.libraryStore)
    }

    @ViewBuilder private var content: some View {
        if let home = homeStore, homeReady {
            rails(home)
        } else if let failureMessage {
            failed(failureMessage)         // the button stays put, saying "Trying…", until it answers
        } else if stillLoading {
            SeretLoader()
        } else {
            empty
        }
    }

    /// Stable ids for the rails — the page scrolls to them, and a tile's focus id is prefixed by
    /// its rail's, so a title in two rails is two distinct focus targets.
    enum Rail {
        static let continueWatching = "continue"
        static let downloading = "downloading"
        static let movies = "movies"
        static let shows = "shows"
        static let picked = "picked"
        static let both = "both"
    }

    /// The rails, each present only while it has something in it. A rail appearing or leaving is
    /// never a swap under a focused tile: an empty rail has nothing in it that could hold focus, and
    /// each rail keeps one id for its whole life.
    private func rails(_ home: HomeStore) -> some View {
        let downloads = activeDownloads
        let picks = watchlistRows
        // Recently Added only stands in for the watchlist rows when there is no Letterboxd account.
        let movies = picks == nil ? home.recentlyAddedMovies : []
        let shows = picks == nil ? home.recentlyAddedShows : []
        let keys = tileKeys(home, picks: picks)
        // Where focus goes: the tile the viewer was last on while it is still there (so coming back
        // from the side menu returns to it), else the tile Home opens on.
        let focusTarget = entryTile.flatMap { keys.contains($0) ? $0 : nil }
            ?? initialFocusID(home, picks: picks)
        return FocusBrowsePage(preview: preview, art: art, initialFocus: focusTarget, focusOnEntry: true,
                               handle: focusHandle) {
            if !home.continueWatching.isEmpty {
                PlexRail(title: "Continue Watching", id: Rail.continueWatching) {
                    ForEach(home.continueWatching) { hi in continueTile(hi, home: home) }
                }
            }
            if !downloads.isEmpty {
                PlexRail(title: "Downloading", id: Rail.downloading) {
                    ForEach(downloads) { tile in
                        let destination = downloadDestination(for: tile, library: session.libraryStore)
                        let key = Self.focusID(Rail.downloading, tile.id)
                        DownloadingRailCard(tile: tile, destination: destination, showsCaption: false,
                                            focusID: key,
                                            onFocus: { focus(Self.subject(for: destination)) })
                    }
                }
            }
            // No See All: these rows are the day's short list, and the whole watchlist is a page
            // of its own.
            if let picks, !picks.picked.isEmpty {
                PlexRail(title: "Picked for Right Now", id: Rail.picked) {
                    ForEach(picks.picked) { entry in watchlistTile(entry, rail: Rail.picked, picks: picks) }
                }
            }
            if let picks, !picks.both.isEmpty {
                PlexRail(title: "Both of You Want to See", id: Rail.both) {
                    ForEach(picks.both) { entry in watchlistTile(entry, rail: Rail.both, picks: picks) }
                }
            }
            if !movies.isEmpty {
                PlexRail(title: "Recently Added Movies", id: Rail.movies) {
                    ForEach(movies) { item in recentTile(item, rail: Rail.movies) }
                }
            }
            if !shows.isEmpty {
                PlexRail(title: "Recently Added Shows", id: Rail.shows) {
                    ForEach(shows) { item in recentTile(item, rail: Rail.shows) }
                }
            }
        }
        // Until a tile has focus, the header shows what the page opens on — and follows it while
        // the rails are still arriving (Recently Added lands before Continue Watching).
        .onChange(of: initialSubject(home, picks: picks), initial: true) { _, subject in
            guard !focusMemory.tileHasFocused, let subject else { return }
            preview.showImmediately(subject)
        }
        // A tile that held focus — or whose long-press menu did — left the rails: marked watched,
        // removed, its download finished. tvOS then leaves NOTHING focused (measured: no ring
        // anywhere, the header still describing the gone title) until the next press, so focus
        // is handed to its neighbour here.
        .onChange(of: keys) { old, new in rehomeFocus(old: old, new: new) }
        // A focused film's details landed after it was focused (a first run): complete its header
        // in place — same title, so nothing fades. Per publish batch, never per press.
        .onChange(of: watchlistDetails?.generation) { _, _ in
            guard let picks, let key = focusHandle.focused,
                  let entry = Self.watchlistEntry(forFocusID: key, in: picks),
                  let shown = preview.shown else { return }
            let fresh = watchlistSubject(entry, picks: picks)
            if fresh.id == shown.id, fresh != shown { preview.showImmediately(fresh) }
        }
        .onAppear { focusHandle.onChange = { tileFocusChanged($0) } }
        // Never move focus by itself while the viewer is in the menu (the rehome checks the menu
        // before every write) or on another page.
        .onChange(of: isVisiblePage) { _, visible in if !visible { cancelRehome() } }
        .onDisappear { cancelRehome() }
        // A rebuild that changed the entry on screen (new progress after watching → a new "Xm
        // left") re-shows it; the focused tile does not re-report focus for a data change. Only
        // while that entry's tile is the focused one, or nothing on the page is: a refresh landing
        // while the viewer glides on would re-show the tile they left — and drop the pending move
        // to the one they are on, freezing the header on the old title.
        .onChange(of: home.continueWatching) { _, entries in
            guard let shown = preview.shown,
                  let entry = entries.first(where: { $0.id == shown.id }) else { return }
            let focused = focusHandle.focused
            guard focused == nil || focused == Self.focusID(Rail.continueWatching, entry.id) else { return }
            let fresh = Self.subject(for: entry)
            if fresh != shown { preview.showImmediately(fresh) }
        }
    }

    /// A Continue Watching tile: progress along its foot, "Next" for an up-next episode, Select
    /// resumes. Press-and-hold to clear it: the rail had no way to remove a title you only started,
    /// so it kept the top of Home for good.
    private func continueTile(_ hi: HomeItem, home: HomeStore) -> some View {
        let key = Self.focusID(Rail.continueWatching, hi.id)
        return PosterTile(posterPath: hi.item.posterPath, title: hi.item.title,
                          progress: hi.fraction, chip: hi.isUpNext ? "Next" : nil,
                          onFocus: { focus(Self.subject(for: hi)) },
                          value: resumeDestination(hi))
            .plexFocusID(key)
            .contextMenu {
                ContinueWatchingActions(entry: hi, home: home, session: session,
                                        openTitle: { openDestination(.detail(hi.item)) },
                                        play: { openDestination(.play($0)) },
                                        didMark: { focusMemory.actedOn = key })
            }
    }

    /// A Recently Added tile: the same ✓ and long-press actions the title carries in My Library.
    private func recentTile(_ item: MediaItem, rail: String) -> some View {
        let key = Self.focusID(rail, item.id)
        return PosterTile(posterPath: item.posterPath, title: item.title,
                          watched: session.libraryStore?.watchState(for: item)?.finished == true,
                          onFocus: { focus(PreviewSubject(item: item)) },
                          value: item)
            .plexFocusID(key)
            .libraryTitleMenu(for: item, session: session, onRemove: {
                focusMemory.actedOn = key
                pendingRemoval = $0
            })
    }

    /// A watchlist film: its poster, whose list it is on ("Both", "Noga") and the grey ✓ when it is
    /// already in the library. Select opens its title page, owned or not. No chip in Both of You
    /// Want to See, where every film would wear the same one.
    private func watchlistTile(_ entry: WatchlistEntry, rail: String, picks: HomeWatchlistRows) -> some View {
        let badge = rail == Rail.both ? nil
            : WatchlistRows.badge(for: entry, membership: picks.membership, partnerName: picks.partnerName)
        return WatchlistTile(entry: entry, owned: isOwned(entry), badge: badge,
                             onFocus: {
                                 // The header's logo, rating and genres from the cache, at once.
                                 if let id = entry.tmdbID, let details = watchlistDetails?.details[id] {
                                     art?.seed(details.titleArt, for: .movie, tmdbID: id)
                                 }
                                 focus(watchlistSubject(entry, picks: picks))
                             },
                             allowsRemove: false)
            .plexFocusID(Self.focusID(rail, entry.id))
    }

    /// A watchlist film's header — built as the Watchlist page builds it, with its tags.
    private func watchlistSubject(_ entry: WatchlistEntry, picks: HomeWatchlistRows) -> PreviewSubject {
        PreviewSubject.watchlist(entry, details: entry.tmdbID.flatMap { watchlistDetails?.details[$0] },
                                 tags: WatchlistRows.tags(for: entry, owned: isOwned(entry),
                                                          membership: picks.membership,
                                                          partnerName: picks.partnerName))
    }

    /// The film behind a `picked/…` or `both/…` focus id, if it is still in that row.
    private static func watchlistEntry(forFocusID key: String, in picks: HomeWatchlistRows) -> WatchlistEntry? {
        for (rail, row) in [(Rail.picked, picks.picked), (Rail.both, picks.both)] {
            let prefix = focusID(rail, "")
            if key.hasPrefix(prefix) {
                let slug = key.dropFirst(prefix.count)
                return row.first { $0.slug == slug }
            }
        }
        return nil
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

    private func isOwned(_ entry: WatchlistEntry) -> Bool {
        guard let id = entry.tmdbID else { return false }
        return session.libraryStore?.ownedItem(tmdbID: id, kind: .movie) != nil
    }

    private func focus(_ subject: PreviewSubject?) {
        focusMemory.tileHasFocused = true
        guard let subject else { return }
        preview.focus(subject)
    }

    static func focusID(_ rail: String, _ id: String) -> String { "\(rail)/\(id)" }

    /// The tile Home opens on: the first tile of the first rail there is — Continue Watching,
    /// Downloading, then Picked for Right Now and Both of You Want to See (or, with no Letterboxd
    /// account, Recently Added Movies and Shows) — the top-leading tile, the one the header starts
    /// on. Downloading counts: with only a download under way there is no other tile, and with no
    /// target launch focus could park on the side menu.
    private func initialFocusID(_ home: HomeStore, picks: HomeWatchlistRows?) -> String? {
        if let hi = home.continueWatching.first { return Self.focusID(Rail.continueWatching, hi.id) }
        if let tile = activeDownloads.first { return Self.focusID(Rail.downloading, tile.id) }
        if let picks {
            if let entry = picks.picked.first { return Self.focusID(Rail.picked, entry.id) }
            return picks.both.first.map { Self.focusID(Rail.both, $0.id) }
        }
        if let movie = home.recentlyAddedMovies.first { return Self.focusID(Rail.movies, movie.id) }
        return home.recentlyAddedShows.first.map { Self.focusID(Rail.shows, $0.id) }
    }

    /// The header for `initialFocusID`'s tile.
    private func initialSubject(_ home: HomeStore, picks: HomeWatchlistRows?) -> PreviewSubject? {
        if let hi = home.continueWatching.first { return Self.subject(for: hi) }
        if let tile = activeDownloads.first {
            return Self.subject(for: downloadDestination(for: tile, library: session.libraryStore))
        }
        if let picks {
            // Read only when a watchlist film IS the opening tile, so Home follows the details
            // store's progress only then — completing that header as its synopsis lands.
            return (picks.picked.first ?? picks.both.first).map { watchlistSubject($0, picks: picks) }
        }
        let first = home.recentlyAddedMovies.first ?? home.recentlyAddedShows.first
        return first.map(PreviewSubject.init(item:))
    }

    /// A Continue Watching entry's header. Its runtime is what the saved position says it is —
    /// `resumeAt` seconds are `fraction` of the whole — so "Xm left" needs no details call. An
    /// up-next entry (nothing watched yet) has no "left".
    private static func subject(for hi: HomeItem) -> PreviewSubject {
        var runtime: Int?
        if let at = hi.resumeAt, at > 0, hi.fraction > 0 {
            runtime = Int((at / hi.fraction / 60).rounded())
        }
        return PreviewSubject(home: hi, runtimeMinutes: runtime)
    }

    /// A download's header: the title it leads to (owned, or the placeholder page).
    private static func subject(for destination: BrowseDestination) -> PreviewSubject? {
        if case .detail(let item) = destination { return PreviewSubject(item: item) }
        return nil
    }

    /// The library could not be read (offline, Real-Debrid down, signed out) and there is no cached
    /// copy. Home used to say "Nothing here yet — play something" about it, for good: the error and
    /// its Try Again only existed in My Library.
    private func failed(_ message: String) -> some View {
        VStack(spacing: 22) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 54))
                .foregroundStyle(Theme.Palette.textSecondary)
            Text(message).bodyText().foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 900)
            // Pressing it used to swap the whole view for a loader — the focused button went, and
            // tvOS put focus on the side menu, which opened by itself. It stays, saying so.
            Button {
                guard !retrying else { return }
                retrying = true
                lastFailure = message
                session.libraryStore?.retry()
            } label: {
                Label(retrying ? "Trying\u{2026}" : "Try Again",
                      systemImage: retrying ? "hourglass" : "arrow.clockwise")
            }
            .buttonStyle(SeretActionButtonStyle(prominent: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Where a Continue Watching card goes: straight into the film, or — only when the file can no
    /// longer be resolved (the version was removed since it was last watched) — to its page.
    ///
    /// It used to push `hi.item` unconditionally, so the old hero's "▶ Resume" and every card in the
    /// rail opened a Detail page instead of resuming: the button said Resume and loaded the same
    /// title's page every time. For a SHOW it was worse — `hi.item` is the series, so the episode
    /// you were part-way through was dropped entirely. The mobile app has resumed directly from
    /// here for a while; this is the same behaviour, expressed as tvOS value-based navigation
    /// (`LibraryShell` already routes a `PlaybackRequest` to the player).
    private func resumeDestination(_ hi: HomeItem) -> BrowseDestination {
        hi.playbackRequest().map { .play($0) } ?? .detail(hi.item)
    }

    private var empty: some View {
        VStack(spacing: 18) {
            SeretMark().frame(width: 90).opacity(0.5)
            Text("Nothing here yet").sectionTitle().foregroundStyle(Theme.Palette.textSecondary)
            Text("Play something and it'll show up here.").bodyText()
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rebuild() async {
        guard let library = session.libraryStore, let home = session.home else { return }
        await home.rebuild(movies: library.movies, shows: library.shows)
    }
}
