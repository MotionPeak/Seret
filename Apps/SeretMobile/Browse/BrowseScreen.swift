import DebridCore
import DebridUI
import SwiftUI

/// The Movies or the Shows tab, as on the Apple TV: ONE page of rows (`DiscoverStore.browseRows`)
/// — up to three "Because you watched…" rows, Trending This Week, New This Month, Top Rated of All
/// Time, then a row per genre — under a glass page header with the Search circle. No segment
/// pills: those stay on the Search page.
///
/// Each genre row has a "See All" in its header and as its last tile; both push that genre's grid
/// (`GenreGridScreen`), seeded with the row's titles so it opens full.
///
/// Rows arrive progressively and only ever at the bottom; a skeleton at the rail metrics holds the
/// space below the last row while more are coming, so nothing on screen moves when one lands.
struct BrowseScreen: View {
    let kind: MediaKind

    @Environment(AppSession.self) private var session
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?
    @State private var pendingRemoval: MediaItem?
    @State private var removeErrorMessage: String?
    @State private var retrying = false

#if DEBUG
    @Environment(\.uiPreviewStores) private var preview
    private var browse: DiscoverStore? {
        (kind == .movie ? preview?.moviesBrowse : preview?.showsBrowse)
            ?? (kind == .movie ? session.moviesBrowse : session.showsBrowse)
    }
#else
    private var browse: DiscoverStore? { kind == .movie ? session.moviesBrowse : session.showsBrowse }
#endif

    /// Changes with what For You is seeded from — the library loading or changing, the profile
    /// resolving.
    private var seedSignature: String {
        let size = (session.libraryStore?.movies.count ?? 0) + (session.libraryStore?.shows.count ?? 0)
        return "\(size)-\(session.activeProfileID ?? "")"
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            if let browse {
                page(browse)
            } else {
                ScrollView { RailSkeleton(rows: 3).padding(.top, Theme.Space.md) }
                    .scrollDisabled(true)
            }
        }
        .glassPageHeader(kind == .movie ? "Movies" : "Shows") {
            SearchCircleLink(kind: kind)
        }
        .navigationDestination(for: GenreRoute.self) { GenreGridScreen(route: $0) }
        .libraryRemovalConfirmation(pending: $pendingRemoval,
                                    errorMessage: $removeErrorMessage,
                                    store: session.libraryStore)
        // The store owns the load; this only asks (and joins one already running). A return to a
        // loaded page is a no-op. Keyed on whether the store exists — it arrives after sign-in.
        .task(id: browse == nil) { await browse?.loadBrowsePage() }
        // A For You built before the library or the profile had landed is rebuilt — quietly, only
        // that block — when they do. On the change only, never because the page reappeared.
        .onChange(of: seedSignature) { _, _ in
            guard let browse else { return }
            Task { await browse.refreshForYouIfBetterSeeds() }
        }
    }

    private func page(_ browse: DiscoverStore) -> some View {
        let rows = browse.browseRows
        let state = browse.browseState
        let width = PosterTileMetrics.width(hSize)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(rows) { row in
                    let route = row.genre.map { GenreRoute(kind: kind, genre: $0, seed: row.hits) }
                    PosterRail(title: row.title, seeAll: route) {
                        ForEach(row.hits) { hit in
                            HitTile(hit: hit, width: width, cam: browse.isCAM(hit.result),
                                    onRemove: { pendingRemoval = $0 })
                        }
                        // Fixed for the row's life (a row's id fixes its genre), so never a branch
                        // swap inside the lazy row.
                        if let route {
                            NavigationLink(value: route) {
                                SeeAllTile(title: route.genre.name, width: width)
                            }
                            .pressable()
                        }
                    }
                    // One batched read per rail; already-known titles cost nothing. Keyed on the row
                    // and its size — a quiet For You rebuild can change a row's titles in place.
                    .task(id: "\(row.id)/\(row.hits.count)") { await marks?.load(row.hits) }
                }
                if state == .failed && rows.isEmpty {
                    failed(browse)
                } else if state != .loaded || rows.isEmpty || browse.browseIsStreaming {
                    // Below the last row while more are still arriving — beside, never inside, the
                    // rails, at their real metrics — so a row lands where its skeleton was.
                    RailSkeleton(rows: rows.isEmpty ? 3 : 1)
                }
            }
            .padding(.top, Theme.Space.xxl)   // clear of the header shade's fade at rest
            .padding(.bottom, Theme.Space.xxxl)
        }
        // Warm the first screenful of posters as rows land.
        .task(id: rows.count) {
            ImageMemoryCache.prefetch(rows.prefix(3).flatMap { $0.hits.prefix(6) }.compactMap {
                TMDBClient.imageURL(path: $0.result.posterPath, size: "w342")
            })
        }
    }

    private func failed(_ browse: DiscoverStore) -> some View {
        VStack(spacing: Theme.Space.lg) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 40))
                .foregroundStyle(Theme.Palette.textSecondary)
            Text("Couldn't load.").font(Theme.Typo.headline())
                .foregroundStyle(Theme.Palette.textPrimary)
            Button {
                guard !retrying else { return }
                retrying = true
                Task {
                    await browse.loadBrowsePage()
                    retrying = false
                }
            } label: {
                Label(retrying ? "Trying…" : "Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PrimaryPillButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

/// A genre row's "See All": the grid it opens, seeded with the row's titles (its first page).
struct GenreRoute: Hashable {
    let kind: MediaKind
    let genre: DiscoverStore.Genre
    let seed: [SearchHit]
}
