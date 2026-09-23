import DebridCore
import DebridUI
import SwiftUI

/// The `.home` section's root: resolves `HomeStore`/`LibraryStore`/`DownloadStore` from the
/// environment (the harness injects fixtures this way) or the live session, and shows the real
/// screen — or a skeleton while no `HomeStore` exists yet (very early in launch, before sign-in
/// resolves).
struct HomeRoot: View {
    @Environment(HomeStore.self) private var injectedHome: HomeStore?
    @Environment(LibraryStore.self) private var injectedLibrary: LibraryStore?
    @Environment(DownloadStore.self) private var injectedDownloads: DownloadStore?
    @Environment(AppSession.self) private var session: AppSession?

    private var home: HomeStore? { injectedHome ?? session?.home }
    private var library: LibraryStore? { injectedLibrary ?? session?.libraryStore }
    private var downloads: DownloadStore? { injectedDownloads ?? session?.downloadStore }

    var body: some View {
        if let home {
            HomeScreen(home: home, library: library, downloads: downloads)
        } else {
            ScrollView { HomeSkeleton() }
                .scrollIndicators(.hidden)
        }
    }
}

/// Home: a full-bleed Continue hero, a Downloading rail, a Continue Watching rail of landscape
/// cards, the Recently Added grid, and loading/empty/failed states — all over the shared
/// `HomeStore`.
struct HomeScreen: View {
    let home: HomeStore
    let library: LibraryStore?
    let downloads: DownloadStore?

    @Environment(AppSession.self) private var session: AppSession?
    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?
    @Environment(WatchlistMarks.self) private var watchlist: WatchlistMarks?
    @Environment(\.pageLeadingInset) private var pageLeadingInset

    private var performer: PosterActionPerformer {
        PosterActionPerformer(session: session, shell: shell, library: library, marks: marks, watchlist: watchlist)
    }

    private var content: HomePageContent {
        HomePageContent.make(library: library?.state, continueWatching: home.continueWatching.count,
                             recentlyAdded: home.recentlyAdded.count,
                             downloading: downloads?.activeTiles.count ?? 0)
    }

    var body: some View {
        Group {
            switch content {
            case .skeleton:
                ScrollView { HomeSkeleton() }.scrollIndicators(.hidden)
            case .empty:
                emptyState
            case .failed(let message):
                failedState(message)
            case .content:
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        heroOrHeader
                        downloadingRail
                        continueWatchingRail
                        recentlyAddedSection
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await rebuild() }
        .onChange(of: library?.movies) { _, _ in Task { await rebuild() } }
        .onChange(of: library?.shows) { _, _ in Task { await rebuild() } }
        .onChange(of: session?.activeProfileID) { _, _ in Task { await rebuild() } }
        .onChange(of: shell?.playbackEndedCount) { _, _ in
            Task {
                await library?.reloadWatchStates()
                await rebuild()
            }
        }
    }

    private func rebuild() async {
        await home.rebuild(movies: library?.movies ?? [], shows: library?.shows ?? [])
    }

    @ViewBuilder private var heroOrHeader: some View {
        if let featured = home.featured {
            HomeHero(entry: featured)
        } else {
            Text("Home")
                .font(Theme.Typo.titleXL())
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.leading, pageLeadingInset)
                .padding(.top, 54)
        }
    }

    @ViewBuilder private var downloadingRail: some View {
        let tiles = downloads?.activeTiles ?? []
        if !tiles.isEmpty {
            PosterRail(title: "Downloading", items: tiles) { tile in
                DownloadingCard(tile: tile, library: library) { item in shell?.open(.title(item)) }
            }
        }
    }

    @ViewBuilder private var continueWatchingRail: some View {
        if !home.continueWatching.isEmpty {
            PosterRail(title: "Continue Watching", items: home.continueWatching,
                       cardHeight: LandscapeCard.artSize.height) { entry in
                LandscapeCard(title: entry.item.title,
                             caption: ContinueCaption.caption(kind: entry.item.kind, subtitle: entry.subtitle,
                                                              resumeAt: entry.resumeAt, fraction: entry.fraction),
                             imageURL: TMDBClient.imageURL(path: entry.item.backdropPath ?? entry.item.posterPath, size: "w780"),
                             fraction: entry.fraction)
                    .contentShape(Rectangle())
                    .onTapGesture { resume(entry) }
                    .contextMenu {
                        Button("Resume") { resume(entry) }
                        Button("Open \u{201C}\(entry.item.title)\u{201D}") { shell?.open(.title(entry.item)) }
                    }
            }
        }
    }

    private func resume(_ entry: HomeItem) {
        if let request = entry.playbackRequest() {
            shell?.present(request)
        } else {
            shell?.open(.title(entry.item))
        }
    }

    @ViewBuilder private var recentlyAddedSection: some View {
        if !home.recentlyAdded.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("RECENTLY ADDED")
                    .font(Theme.Typo.label())
                    .tracking(1.5)
                    .foregroundStyle(Theme.Palette.gold)
                    .padding(.leading, pageLeadingInset)
                PosterGrid(items: home.recentlyAdded) { item in
                    recentlyAddedTile(item)
                }
                .padding(.leading, pageLeadingInset)
                .padding(.trailing, 28)
            }
        }
    }

    private func recentlyAddedTile(_ item: MediaItem) -> some View {
        let model = PosterTileModel.library(item)
        let watchState = library?.watchState(for: item)
        let onWatchlist = model.watchlistFilm.map { watchlist?.contains(tmdbID: $0.tmdbID) ?? false } ?? false
        return PosterTile(model: model,
                          state: PosterTileState(badge: WatchBadge(watchState), decor: PosterDecor(dimsWatched: true)),
                          actions: .make(kind: item.kind, owned: true, watched: watchState?.finished ?? false, onWatchlist: onWatchlist),
                          perform: performer.perform)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            SeretMark(glow: false)
                .frame(width: 90, height: 90)
                .opacity(0.5)
            Text("Nothing here yet")
                .font(Theme.Typo.headline())
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("Add something to your Real\u{2011}Debrid account, or play something, and it shows up here.")
                .font(Theme.Typo.body())
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(Theme.Palette.gold)
            Text(message)
                .font(Theme.Typo.headline())
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.center)
            Button("Try Again") { library?.retry() }
                .buttonStyle(GlassButtonStyle())
                .padding(.top, 4)
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Home's loading state: a hero-height shimmer, a landscape rail skeleton and a three-row poster
/// grid skeleton — same shapes as the content that replaces them, so nothing jumps when it lands.
/// Also what `HomeRoot` shows before a `HomeStore` exists at all.
struct HomeSkeleton: View {
    @Environment(\.pageLeadingInset) private var pageLeadingInset

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            ShimmerView(cornerRadius: 0)
                .frame(maxWidth: .infinity)
                .frame(height: TitlePageLayout.heroHeight(width: 1200))
            RailSkeleton(cardSize: LandscapeCard.artSize, count: 5)
            PosterGrid(items: [MediaItem](), isLoading: true) { (_: MediaItem) in EmptyView() }
                .padding(.leading, pageLeadingInset)
                .padding(.trailing, 28)
        }
        .padding(.bottom, 40)
    }
}
