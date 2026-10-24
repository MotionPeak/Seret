import DebridCore
import DebridUI
import SwiftUI

/// Your Real-Debrid library: everything you have added, as a poster grid under the glass page
/// header ("Library", how many of each), with Movies / Shows glass pills to switch between them.
///
/// - Downloads in flight sit above the grid as a rail of the same tiles Home's Downloading rail
///   uses — tappable, to the same destination (the title's page).
/// - The grid is adaptive (about three across an iPhone, five to seven on iPad), each poster
///   captioned, watched ones dimmed with a white ✓. The long-press is the library menu every
///   library title has (mark watched, remove), with the same confirm-then-remove alerts.
struct MyLibraryScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var kind: MediaKind = .movie
    @State private var pendingRemoval: MediaItem?
    @State private var removeErrorMessage: String?

#if DEBUG
    @Environment(\.uiPreviewStores) private var preview
    private var store: LibraryStore? { preview?.library ?? session.libraryStore }
    private var downloads: [DownloadTile] { preview?.downloads ?? session.downloadStore?.activeTiles ?? [] }
#else
    private var store: LibraryStore? { session.libraryStore }
    private var downloads: [DownloadTile] { session.downloadStore?.activeTiles ?? [] }
#endif

    var body: some View {
        ZStack {
            CanvasBackground()
            if let store {
                page(store)
                    .task(id: store.attempt) { await store.load() }
                    // Watch state is per profile — re-read the ✓ marks when the profile changes.
                    .task(id: session.activeProfileID) { await store.reloadWatchStates() }
            } else {
                ScrollView { skeleton }.scrollDisabled(true)
            }
        }
        .glassPageHeader("Library", subtitle: countLine) {
            SearchCircleLink(kind: kind)
        }
        .libraryRemovalConfirmation(pending: $pendingRemoval, errorMessage: $removeErrorMessage,
                                    store: store)
    }

    /// "142 movies · 31 shows", once the library has loaded.
    private var countLine: String? {
        guard let store, store.state == .loaded else { return nil }
        func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
        return count(store.movies.count, "movie", "movies") + " · " + count(store.shows.count, "show", "shows")
    }

    private func items(_ store: LibraryStore) -> [MediaItem] {
        kind == .movie ? store.movies : store.shows
    }

    private func page(_ store: LibraryStore) -> some View {
        let items = items(store)
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                kindPills
                if !downloads.isEmpty { downloadingRail }
                content(store, items: items)
            }
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.xxxl)
        }
        // Warm the first screenful of posters when the grid's data lands.
        .task(id: "\(kind)-\(items.count)") {
            ImageMemoryCache.prefetch(items.prefix(18).compactMap {
                TMDBClient.imageURL(path: $0.posterPath, size: "w342")
            })
        }
    }

    /// Movies / Shows: solid white when selected, glass at rest — the genre grid's sort pills.
    private var kindPills: some View {
        HStack(spacing: Theme.Space.sm) {
            ForEach([MediaKind.movie, .show], id: \.self) { k in
                let selected = kind == k
                Button(k == .movie ? "Movies" : "Shows") {
                    withAnimation(Theme.Motion.quick) { kind = k }
                }
                .buttonStyle(SortPillStyle(selected: selected))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, PosterTileMetrics.margin(hSize))
    }

    /// Downloads in flight, as on Home — a tap opens what is landing.
    private var downloadingRail: some View {
        PosterRail(title: "Downloading") {
            ForEach(downloads) { tile in
                Button {
                    openDownload(tile, library: store, router: router)
                } label: {
                    DownloadingTile(tile: tile, width: PosterTileMetrics.width(hSize), showsTitle: true)
                }
                .pressable()
            }
        }
    }

    @ViewBuilder private func content(_ store: LibraryStore, items: [MediaItem]) -> some View {
        switch store.state {
        case .loading:
            skeleton
        case .failed(let message):
            GlassMessageCard(systemImage: "exclamationmark.triangle", title: "Couldn't load your library",
                             text: message, topPadding: 40) {
                PrimaryPill(title: "Try Again", systemImage: "arrow.clockwise") { store.retry() }
            }
        case .empty:
            GlassMessageCard(systemImage: "tray", title: "Nothing in your library yet",
                             text: "Add something from Search, or to \(DebridCopy.accounts(session.signedInProviders)), and it appears here.",
                             topPadding: 40) {
                EmptyView()
            }
        case .loaded:
            if items.isEmpty {
                GlassMessageCard(systemImage: "tray",
                                 title: kind == .movie ? "No movies yet" : "No shows yet",
                                 text: "Titles you add show up here.", topPadding: 40) {
                    EmptyView()
                }
            } else {
                grid(store, items: items)
            }
        }
    }

    private func grid(_ store: LibraryStore, items: [MediaItem]) -> some View {
        LazyVGrid(columns: PosterTileMetrics.gridColumns(hSize), spacing: PosterTileMetrics.spacing + 6) {
            ForEach(items) { item in
                Button { router.detail = item } label: {
                    PosterTile(posterPath: item.posterPath, title: item.title, width: nil,
                               // By id, shows included (a series hangs off its own key).
                               watched: store.watchByKey[item.id]?.finished == true,
                               showsTitle: true)
                }
                .pressable()
                .libraryTitleMenu(for: item, session: session, onRemove: { pendingRemoval = $0 })
            }
        }
        .padding(.horizontal, PosterTileMetrics.margin(hSize))
    }

    /// Loading posters at the grid's own metrics.
    private var skeleton: some View {
        LazyVGrid(columns: PosterTileMetrics.gridColumns(hSize), spacing: PosterTileMetrics.spacing + 6) {
            ForEach(0..<12, id: \.self) { _ in
                RoundedRectangle(cornerRadius: PosterTileMetrics.corner, style: .continuous)
                    .fill(Theme.Palette.surface1)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
            }
        }
        .padding(.horizontal, PosterTileMetrics.margin(hSize))
        .padding(.top, Theme.Space.md)
        .accessibilityHidden(true)
    }
}
