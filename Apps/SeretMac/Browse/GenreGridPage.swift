import DebridCore
import DebridUI
import SwiftUI

/// One genre's own grid: Popular/New/Top Rated over `GenreGridStore`'s infinite scroll (capped at
/// 10 pages). Rebuilt only when the genre id really changes (`.task(id: genre.tmdbID)` guarded by
/// `loadedGenreID`) — pushing a title and coming back must not reset the pages already loaded.
struct GenreGridPage: View {
    let kind: MediaKind
    let genre: DiscoverStore.Genre
    let sources: BrowseSources

    @Environment(AppSession.self) private var session: AppSession?
    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(LibraryStore.self) private var injectedLibrary: LibraryStore?
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?
    @Environment(WatchlistMarks.self) private var watchlist: WatchlistMarks?
    @Environment(\.pageLeadingInset) private var pageLeadingInset

    @State private var store: GenreGridStore?
    @State private var loadedGenreID: Int?

    private var library: LibraryStore? { injectedLibrary ?? session?.libraryStore }
    private var performer: PosterActionPerformer {
        PosterActionPerformer(session: session, shell: shell, library: library, marks: marks, watchlist: watchlist)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let store {
                CapsuleSegments(options: GenreSort.allCases, title: \.title, selection: store.sort,
                                onSelect: { sort in Task { await store.select(sort: sort) } })
                    .padding(.leading, pageLeadingInset)
            }
            content
        }
        .task(id: genre.tmdbID) {
            guard loadedGenreID != genre.tmdbID else { return }
            loadedGenreID = genre.tmdbID
            let fresh = sources.makeGenreGrid(kind, genre)
            store = fresh
            await fresh?.load()
        }
    }

    @ViewBuilder private var content: some View {
        if let store {
            switch store.state {
            case .idle, .loading:
                loadingGrid
            case .failed:
                failedState
            case .loaded:
                VStack(alignment: .leading, spacing: 0) {
                    PosterGrid(items: store.hits, onItemAppear: { hit in
                        if PagingTrigger.shouldLoadMore(appeared: hit.id, in: store.hits.map(\.id)) {
                            Task { await store.loadMore() }
                        }
                    }) { hit in tile(hit) }
                    .padding(.leading, pageLeadingInset)
                    .padding(.trailing, 28)
                    if !store.reachedEnd {
                        GridFooterSkeleton()
                            .padding(.leading, pageLeadingInset)
                            .padding(.trailing, 28)
                    }
                }
                .task(id: store.hits.map(\.id)) { await marks?.load(store.hits) }
            }
        } else {
            loadingGrid
        }
    }

    private var loadingGrid: some View {
        PosterGrid(items: [SearchHit](), isLoading: true) { (_: SearchHit) in EmptyView() }
            .padding(.leading, pageLeadingInset)
            .padding(.trailing, 28)
    }

    private func tile(_ hit: SearchHit) -> some View {
        let model = PosterTileModel.hit(hit, library: library, isCAM: false)
        let watched = marks?.isWatched(hit) ?? false
        let onWatchlist = model.watchlistFilm.map { watchlist?.contains(tmdbID: $0.tmdbID) ?? false } ?? false
        let badge: WatchBadge = watched ? .watched : .none
        let decor = PosterDecor(owned: model.owned != nil, onWatchlist: onWatchlist, dimsWatched: true)
        return PosterTile(model: model, state: PosterTileState(badge: badge, decor: decor),
                          actions: .make(kind: hit.kind, owned: model.owned != nil, watched: watched, onWatchlist: onWatchlist),
                          perform: performer.perform)
    }

    private var failedState: some View {
        VStack(spacing: 12) {
            Text("Nothing here.")
                .font(Theme.Typo.headline())
                .foregroundStyle(Theme.Palette.textPrimary)
            Button("Try Again") { Task { await store?.load() } }
                .buttonStyle(GlassButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

/// One row of card-sized skeletons under a genre grid's loaded content, sized to the same column
/// count the grid itself just laid out — so the grid's height never jumps when the next page lands
/// in their place.
private struct GridFooterSkeleton: View {
    @State private var width: CGFloat = 0

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: PosterGridLayout.cardWidth, maximum: PosterGridLayout.cardWidth),
                 spacing: PosterGridLayout.spacing)]
    }

    var body: some View {
        let count = PosterGridLayout(availableWidth: width).columns
        LazyVGrid(columns: columns, alignment: .leading, spacing: PosterGridLayout.rowSpacing) {
            ForEach(0..<count, id: \.self) { _ in CardSkeleton() }
        }
        .padding(.top, 12)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
