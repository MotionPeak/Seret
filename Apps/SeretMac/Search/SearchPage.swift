import DebridCore
import DebridUI
import SwiftUI

/// The root of Search's own stack: the query in quotes, an All/Movies/Shows scope, and the
/// per-window `SearchStore`'s results — debounced 350 ms after the last keystroke so a fast typist
/// doesn't fire a request per character.
struct SearchPage: View {
    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(\.searchStore) private var store: SearchStore?
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(LibraryStore.self) private var injectedLibrary: LibraryStore?
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?
    @Environment(WatchlistMarks.self) private var watchlist: WatchlistMarks?
    @Environment(\.pageLeadingInset) private var pageLeadingInset

    private var library: LibraryStore? { injectedLibrary ?? session?.libraryStore }
    private var performer: PosterActionPerformer {
        PosterActionPerformer(session: session, shell: shell, library: library, marks: marks, watchlist: watchlist)
    }
    private var requestKey: SearchRequestKey {
        SearchRequestKey(query: shell?.searchQuery ?? "", scope: shell?.searchScope ?? .all)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let shell {
                CapsuleSegments(options: SearchScope.allCases, title: \.title, selection: shell.searchScope,
                                onSelect: { shell.searchScope = $0 })
                    .padding(.leading, pageLeadingInset)
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: requestKey) { await debouncedSearch() }
    }

    private func debouncedSearch() async {
        let key = requestKey
        guard !key.isEmpty, let store else { return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }     // a newer keystroke owns the search
        await store.search(query: key.query, kind: key.scope.kind)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Search")
                .font(Theme.Typo.titleXL())
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("\u{201C}\(shell?.searchQuery ?? "")\u{201D}")
                .font(Theme.Typo.caption())
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.leading, pageLeadingInset)
        .padding(.top, 54)
    }

    @ViewBuilder private var content: some View {
        if let store {
            switch store.state {
            case .idle:
                idleState
            case .searching:
                scrolling(loadingGrid)
            case .results:
                scrolling(
                    PosterGrid(items: store.results,
                               prefetchURL: { TMDBClient.imageURL(path: $0.result.posterPath, size: "w342") }) { hit in tile(hit) }
                        .padding(.leading, pageLeadingInset)
                        .padding(.trailing, 28)
                )
                .task(id: store.results.map(\.id)) { await marks?.load(store.results) }
            case .empty:
                emptyState
            case .failed(let message):
                failedState(message)
            }
        } else {
            idleState
        }
    }

    /// The results scroll under the fixed title and scope switch, the way My Library's grid does.
    /// The page used to have no scroll view at all, so a long result list made it — and with it the
    /// whole window's content — taller than the window: the sidebar, the search field and Back were
    /// pushed off the top, and nothing could be scrolled.
    private func scrolling(_ grid: some View) -> some View {
        ScrollView {
            grid.padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
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

    private var idleState: some View {
        Text("Type a title to search.")
            .font(Theme.Typo.body())
            .foregroundStyle(Theme.Palette.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(Theme.Palette.gold)
            Text("No results for \u{201C}\(shell?.searchQuery ?? "")\u{201D}")
                .font(Theme.Typo.headline())
                .foregroundStyle(Theme.Palette.textPrimary)
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
            Button("Try Again") {
                Task { await store?.search(query: shell?.searchQuery ?? "", kind: shell?.searchScope.kind) }
            }
            .buttonStyle(GlassButtonStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
