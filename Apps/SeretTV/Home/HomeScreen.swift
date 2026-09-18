import DebridCore
import DebridUI
import SwiftUI

/// Home tab: a featured hero (most recent Continue item), a Continue Watching rail and a Recently
/// Added grid, composed on the shared `session.home`. Cards push library Detail.
struct HomeScreen: View {
    @Environment(AppSession.self) private var session

    /// The hero's "Resume" capsule is painted content inside a `.card` link, not a Button, so it had
    /// no way to know whether the hero held focus — it drew a full gold gradient and a permanent
    /// glow at all times. On a screen where the Search pill starts focused that reads as two
    /// focused things at once, and the capsule looks pressable when it is only decoration. Tracking
    /// the link's focus lets the capsule use the same resting/focused treatment as every real CTA.
    @FocusState private var heroFocused: Bool

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

    /// True once there's anything to show.
    private var homeReady: Bool {
        guard let h = homeStore else { return false }
        return !(h.continueWatching.isEmpty && h.recentlyAdded.isEmpty)
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
        .task { await rebuild() }
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
                                    LandscapeProgressCard(title: hi.item.title, subtitle: hi.subtitle,
                                                          imageURL: backdropURL(hi.item), fraction: hi.fraction)
                                }.buttonStyle(.card)
                                    // Press-and-hold to clear it: the rail had no way to remove a
                                    // title you only started, so it kept the top of Home for good.
                                    .contextMenu { ContinueWatchingActions(entry: hi, home: home, session: session) }
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
        } else {
            empty
        }
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

    @ViewBuilder private func hero(_ home: HomeStore) -> some View {
        if let f = home.featured {
            NavigationLink(value: resumeDestination(f)) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(url: backdropURL(f.item))
                        .frame(height: 620).frame(maxWidth: .infinity).clipped()
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Theme.Palette.canvas.opacity(0.7), location: 0.6),
                        .init(color: Theme.Palette.canvas, location: 1.0),
                    ], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 14) {
                        Text(f.subtitle.isEmpty ? "Continue Watching" : "Continue · \(f.subtitle)")
                            .eyebrow().foregroundStyle(Theme.Palette.gold)
                        Text(f.item.title).heroTitle()
                            .foregroundStyle(Theme.Palette.textPrimary).lineLimit(2)
                        HStack(spacing: 10) { Image(systemName: "play.fill"); Text("Resume") }
                            .font(.seret(.title3, .semibold)).foregroundStyle(.black)
                            .padding(.vertical, 14).padding(.horizontal, 40)
                            .background(heroFocused ? AnyShapeStyle(Theme.Palette.goldGradient)
                                                    : AnyShapeStyle(Theme.Palette.goldDeep),
                                        in: Capsule())
                            .overlay(Capsule().strokeBorder(
                                heroFocused ? Theme.Palette.goldBright : .white.opacity(0.10),
                                lineWidth: heroFocused ? 3 : 1))
                            .goldGlow(heroFocused ? 16 : 0, opacity: 0.4)
                            .animation(Theme.Anim.focus, value: heroFocused)
                    }
                    .padding(60)
                }
            }
            .buttonStyle(.card)
            .focused($heroFocused)
        }
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
