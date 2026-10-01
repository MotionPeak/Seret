import DebridCore
import DebridUI
import SwiftUI

/// Home tab: a featured hero (most recent Continue item), a Continue Watching rail and a Recently
/// Added grid, composed on the shared `session.home`. Cards push library Detail.
struct HomeScreen: View {
    @Environment(AppSession.self) private var session
    /// Pushes a page onto the shell's stack. A no-op outside the shell (previews, the harness).
    @Environment(\.openBrowseDestination) private var openDestination

    /// A title awaiting removal confirmation, and the failure to surface if RD refuses. Home hosts
    /// these itself because a rail is a place you remove from, not only a place you browse.
    @State private var pendingRemoval: MediaItem?
    @State private var removeErrorMessage: String?

#if DEBUG
    /// The store the `-uiPreview home` harness renders instead of the session's, so the real screen
    /// — hero, rail and grid together — can be screenshot-verified without a signed-in session and
    /// without a watch history the simulator has no cheap way to produce.
    var previewHome: HomeStore?
    private var homeStore: HomeStore? { previewHome ?? session.home }
#else
    private var homeStore: HomeStore? { session.home }
#endif

    /// True once there's anything to show — a download under way counts: a first title being fetched
    /// into an empty library is exactly when the viewer wants to see it.
    private var homeReady: Bool {
        guard let h = homeStore else { return false }
        if !(session.downloadStore?.activeTiles.isEmpty ?? true) { return true }
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 50) {
                    hero(home)
                    if let tiles = session.downloadStore?.activeTiles, !tiles.isEmpty {
                        HomeRail(title: "Downloading") {
                            ForEach(tiles) { tile in
                                DownloadingRailCard(
                                    tile: tile,
                                    destination: downloadDestination(for: tile,
                                                                     library: session.libraryStore))
                            }
                        }
                    }
                    if !home.continueWatching.isEmpty {
                        HomeRail(title: "Continue Watching") {
                            ForEach(home.continueWatching) { hi in
                                NavigationLink(value: resumeDestination(hi)) {
                                    LandscapeProgressCard(title: hi.item.title,
                                                          subtitle: hi.isUpNext ? "Next · \(hi.subtitle)" : hi.subtitle,
                                                          imageURL: backdropURL(hi.item), fraction: hi.fraction)
                                }.buttonStyle(.card)
                                    // Press-and-hold to clear it: the rail had no way to remove a
                                    // title you only started, so it kept the top of Home for good.
                                    .contextMenu {
                                        ContinueWatchingActions(entry: hi, home: home, session: session,
                                                                openTitle: { openDestination(.detail(hi.item)) },
                                                                play: { openDestination(.play($0)) })
                                    }
                            }
                        }
                    }
                    if !home.recentlyAdded.isEmpty {
                        // A grid, not a rail: this is the section you browse, and sideways it
                        // showed six of sixty while the rest of the page sat empty. `PosterCard`
                        // rather than a private copy, so a title here carries the same ✓, the same
                        // label and the same long-press actions it does in My Library.
                        HomeGrid(title: "Recently Added") {
                            ForEach(home.recentlyAdded) { item in
                                PosterCard(item: item,
                                           watched: session.libraryStore?.watchState(for: item)?.finished == true,
                                           session: session,
                                           onRemove: { pendingRemoval = $0 })
                            }
                        }
                    }
                }
                .padding(.vertical, 40)
            }
        } else if let failureMessage {
            failed(failureMessage)         // the button stays put, saying "Trying…", until it answers
        } else if stillLoading {
            SeretLoader()
        } else {
            empty
        }
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
    /// It used to push `hi.item` unconditionally, so the hero's "▶ Resume" and every card in the
    /// rail opened a Detail page instead of resuming: the button said Resume and loaded the same
    /// title's page every time. For a SHOW it was worse — `hi.item` is the series, so the episode
    /// you were part-way through was dropped entirely. The mobile app has resumed directly from
    /// here for a while; this is the same behaviour, expressed as tvOS value-based navigation
    /// (`LibraryShell` already routes a `PlaybackRequest` to the player).
    private func resumeDestination(_ hi: HomeItem) -> BrowseDestination {
        hi.playbackRequest().map { .play($0) } ?? .detail(hi.item)
    }

    /// The billboard: artwork you look at, with real buttons you press — the Netflix / HBO shape.
    ///
    /// It used to be ONE full-width `.card` link with a painted "Resume" capsule inside it. Focus
    /// then belonged to the whole 1600pt-wide card, and tvOS measures a move from the CENTRE of the
    /// focused view, so pressing DOWN from "Resume" landed on whichever Continue Watching card sat
    /// under the middle of the screen (the second one) instead of the card right below the button.
    /// There was also no way from Home to a title's page — every surface here resumed.
    @ViewBuilder private func hero(_ home: HomeStore) -> some View {
        if let f = home.featured {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: backdropURL(f.item))
                    .frame(height: 620).frame(maxWidth: .infinity).clipped()
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Theme.Palette.canvas.opacity(0.7), location: 0.6),
                    .init(color: Theme.Palette.canvas, location: 1.0),
                ], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 14) {
                    Text(f.isUpNext ? "Up Next · \(f.subtitle)"
                         : f.subtitle.isEmpty ? "Continue Watching" : "Continue · \(f.subtitle)")
                        .eyebrow().foregroundStyle(Theme.Palette.gold)
                    Text(f.item.title).heroTitle()
                        .foregroundStyle(Theme.Palette.textPrimary).lineLimit(2)
                    HStack(spacing: 16) {
                        // A file that no longer resolves cannot resume — then the page is the
                        // only honest destination, and it becomes the primary button.
                        if let request = f.playbackRequest() {
                            NavigationLink(value: BrowseDestination.play(request)) {
                                Label(resumeLabel(f), systemImage: "play.fill")
                            }
                            .buttonStyle(SeretActionButtonStyle(prominent: true))
                        }
                        NavigationLink(value: BrowseDestination.detail(f.item)) {
                            Label("Details", systemImage: "info.circle")
                        }
                        .buttonStyle(SeretActionButtonStyle(prominent: !f.isResumable))
                    }
                    .padding(.top, 8)
                }
                .padding(60)
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    /// "Resume 34:16" when the saved position is known — the same words the title page uses, so the
    /// two screens never disagree about what the button will do.
    private func resumeLabel(_ f: HomeItem) -> String {
        if f.isUpNext { return "Play" }          // the next episode, from its start
        guard let at = f.resumeAt, at > 0 else { return "Resume" }
        return "Resume \(Timecode.format(at))"
    }

    private var empty: some View {
        VStack(spacing: 18) {
            SeretMark(glow: false).frame(width: 90).opacity(0.5)
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

    private func backdropURL(_ i: MediaItem) -> URL? {
        TMDBClient.imageURL(path: i.backdropPath ?? i.posterPath, size: "w1280")
    }
}
