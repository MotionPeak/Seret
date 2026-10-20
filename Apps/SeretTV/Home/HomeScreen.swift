import DebridCore
import DebridUI
import SwiftUI

/// Home tab, Plex-style: a focus-driven preview header (logo, metadata, synopsis over the ultrablur
/// backdrop of the focused title) above sideways poster rails — Continue Watching, Downloading
/// (while anything is), Recently Added Movies and Recently Added Shows — composed on the shared
/// `session.home`.
///
/// Continue Watching resumes on Select (its page only when the file no longer resolves) and keeps
/// its press-and-hold menu; Recently Added tiles open the title's page and keep the library menu and
/// the watched ✓; Downloading tiles open the title's page.
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
#else
    private var homeStore: HomeStore? { session.home }
    private var art: TitleArtStore? { session.titleArt }
    var activeDownloads: [DownloadTile] { session.downloadStore?.activeTiles ?? [] }
#endif

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
        if !activeDownloads.isEmpty { return true }
        return !(h.continueWatching.isEmpty && h.recentlyAdded.isEmpty)
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
    private var stillLoading: Bool {
        guard let library = session.libraryStore else { return false }
        return library.state == .loading || !(library.movies.isEmpty && library.shows.isEmpty)
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
        .task { await rebuild() }
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
    }

    /// The rails, each present only while it has something in it. A rail appearing or leaving is
    /// never a swap under a focused tile: an empty rail has nothing in it that could hold focus, and
    /// each rail keeps one id for its whole life.
    private func rails(_ home: HomeStore) -> some View {
        let downloads = activeDownloads
        let movies = home.recentlyAddedMovies
        let shows = home.recentlyAddedShows
        let keys = tileKeys(home)
        // Where focus goes: the tile the viewer was last on while it is still there (so coming back
        // from the side menu returns to it), else the tile Home opens on.
        let focusTarget = entryTile.flatMap { keys.contains($0) ? $0 : nil } ?? initialFocusID(home)
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
        .onChange(of: initialSubject(home), initial: true) { _, subject in
            guard !focusMemory.tileHasFocused, let subject else { return }
            preview.showImmediately(subject)
        }
        // A tile that held focus — or whose long-press menu did — left the rails: marked watched,
        // removed, its download finished. tvOS then leaves NOTHING focused (measured: no ring
        // anywhere, the header still describing the gone title) until the next press, so focus
        // is handed to its neighbour here.
        .onChange(of: keys) { old, new in rehomeFocus(old: old, new: new) }
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

    private func focus(_ subject: PreviewSubject?) {
        focusMemory.tileHasFocused = true
        guard let subject else { return }
        preview.focus(subject)
    }

    static func focusID(_ rail: String, _ id: String) -> String { "\(rail)/\(id)" }

    /// The tile Home opens on: the first tile of the first rail there is — Continue Watching,
    /// Downloading, Recently Added Movies, Recently Added Shows — the top-leading tile, the one the
    /// header starts on. Downloading counts: with only a download under way there is no other
    /// tile, and with no target launch focus could park on the side menu.
    private func initialFocusID(_ home: HomeStore) -> String? {
        if let hi = home.continueWatching.first { return Self.focusID(Rail.continueWatching, hi.id) }
        if let tile = activeDownloads.first { return Self.focusID(Rail.downloading, tile.id) }
        if let movie = home.recentlyAddedMovies.first { return Self.focusID(Rail.movies, movie.id) }
        return home.recentlyAddedShows.first.map { Self.focusID(Rail.shows, $0.id) }
    }

    /// The header for `initialFocusID`'s tile.
    private func initialSubject(_ home: HomeStore) -> PreviewSubject? {
        if let hi = home.continueWatching.first { return Self.subject(for: hi) }
        if let tile = activeDownloads.first {
            return Self.subject(for: downloadDestination(for: tile, library: session.libraryStore))
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
