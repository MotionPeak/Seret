import DebridCore
import DebridUI
import SwiftUI

/// One genre's full grid, pushed from a Movies/Shows genre row's "See All". Opens on the row's own
/// titles (the Popular sort's first page — `GenreGridStore(seed:)`), so it is full from its first
/// frame, then pages on as you scroll. Popular / New / Top Rated are glass pills under the title.
struct GenreGridScreen: View {
    let route: GenreRoute

    @Environment(AppSession.self) private var session
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?
    @State private var store: GenreGridStore?
    @State private var pendingRemoval: MediaItem?
    @State private var removeErrorMessage: String?
#if DEBUG
    @Environment(\.uiPreviewStores) private var preview
#endif

    var body: some View {
        ZStack {
            CanvasBackground()
            if let store {
                grid(store)
            } else {
                ProgressView().tint(Theme.Palette.focus)
            }
        }
        .navigationTitle(route.genre.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .libraryRemovalConfirmation(pending: $pendingRemoval,
                                    errorMessage: $removeErrorMessage,
                                    store: session.libraryStore)
        .task {
            if store == nil { store = makeStore() }
            await store?.load()
        }
    }

    private func makeStore() -> GenreGridStore? {
#if DEBUG
        if let browsing = preview?.genreBrowsing {
            return GenreGridStore(kind: route.kind, genre: route.genre, browsing: browsing, seed: route.seed)
        }
#endif
        return session.makeGenreGrid(kind: route.kind, genre: route.genre, seed: route.seed)
    }

    private func grid(_ store: GenreGridStore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                sortPills(store)
                if store.hits.isEmpty && store.state == .failed {
                    message("Couldn't load", systemImage: "exclamationmark.triangle")
                } else if store.hits.isEmpty && store.state == .loaded {
                    message("No titles", systemImage: "film")
                } else if store.hits.isEmpty {
                    ProgressView().tint(Theme.Palette.focus)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    LazyVGrid(columns: PosterTileMetrics.gridColumns(hSize),
                              spacing: PosterTileMetrics.spacing + 4) {
                        ForEach(store.hits) { hit in
                            HitTile(hit: hit, width: nil, cam: isCAM(hit), onRemove: { pendingRemoval = $0 })
                                .onAppear {
                                    // The last row coming into view asks for the next page.
                                    if hit.id == store.hits.last?.id { Task { await store.loadMore() } }
                                }
                        }
                    }
                    .padding(.horizontal, PosterTileMetrics.margin(hSize))
                    if !store.reachedEnd {
                        ProgressView().tint(Theme.Palette.focus).frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Space.lg)
                    }
                }
            }
            .padding(.bottom, Theme.Space.xxxl)
        }
        .task(id: store.hits.count) { await marks?.load(store.hits) }
    }

    /// Theatrical-window films carry the CAM chip here as in the rows they came from.
    private func isCAM(_ hit: SearchHit) -> Bool {
        guard route.kind == .movie else { return false }
#if DEBUG
        if let browse = preview?.moviesBrowse { return browse.isCAM(hit.result) }
#endif
        return session.moviesBrowse?.isCAM(hit.result) ?? false
    }

    private func sortPills(_ store: GenreGridStore) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                ForEach(GenreSort.allCases) { sort in
                    let selected = store.sort == sort
                    Button(sort.title) { Task { await store.select(sort: sort) } }
                        .buttonStyle(SortPillStyle(selected: selected))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, PosterTileMetrics.margin(hSize))
            .padding(.vertical, 4)
        }
    }

    private func message(_ text: String, systemImage: String) -> some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: systemImage).font(.system(size: 40)).foregroundStyle(Theme.Palette.textSecondary)
            Text(text).font(Theme.Typo.headline()).foregroundStyle(Theme.Palette.textPrimary)
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }
}

/// A filter pill: solid white when selected, glass at rest.
struct SortPillStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if selected {
                configuration.label
                    .foregroundStyle(Theme.Palette.onFocus)
                    .padding(.vertical, 9).padding(.horizontal, Theme.Space.lg)
                    .background(Theme.Palette.focus, in: Capsule())
            } else {
                configuration.label
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .padding(.vertical, 9).padding(.horizontal, Theme.Space.lg)
                    .seretGlass(in: Capsule())
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
