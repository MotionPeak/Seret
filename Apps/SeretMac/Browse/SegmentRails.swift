import DebridCore
import DebridUI
import SwiftUI

/// **All**'s content: the For You/Trending/New/Popular/Top Rated segment bar over a stack of
/// horizontal rails. Rails arrive progressively (`DiscoverStore.loadSegment` publishes each rail as
/// it completes) and never reorder — a rail keeps its `id`, so one landing below never moves the
/// ones already on screen.
struct SegmentRails: View {
    let store: DiscoverStore
    let kind: MediaKind

    @Environment(AppSession.self) private var session: AppSession?
    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(LibraryStore.self) private var injectedLibrary: LibraryStore?
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?
    @Environment(WatchlistMarks.self) private var watchlist: WatchlistMarks?
    @Environment(\.pageLeadingInset) private var pageLeadingInset

    private var library: LibraryStore? { injectedLibrary ?? session?.libraryStore }
    private var performer: PosterActionPerformer {
        PosterActionPerformer(session: session, shell: shell, library: library, marks: marks, watchlist: watchlist)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CapsuleSegments(options: DiscoverStore.Segment.allCases, title: \.title,
                            selection: store.selectedSegment, onSelect: { store.select($0) })
                .padding(.leading, pageLeadingInset)
            content
        }
        // Keyed on `kind` too — a Movies/Shows switch must restart the load, not reuse a stale id.
        .task(id: "\(kind.rawValue)/\(store.selectedSegment.rawValue)") {
            await store.loadSegment(store.selectedSegment)
        }
    }

    @ViewBuilder private var content: some View {
        switch store.segmentState(store.selectedSegment) {
        case .idle, .loading:
            VStack(alignment: .leading, spacing: 26) {
                RailSkeleton()
                RailSkeleton()
                RailSkeleton()
            }
        case .failed:
            failedState
        case .loaded:
            LazyVStack(alignment: .leading, spacing: 26) {
                ForEach(store.rows) { row in
                    PosterRail(title: row.title, items: row.hits) { hit in tile(hit) }
                        .task(id: row.hits.map(\.id)) { await marks?.load(row.hits) }
                }
            }
        }
    }

    private func tile(_ hit: SearchHit) -> some View {
        let model = PosterTileModel.hit(hit, library: library, isCAM: store.isCAM(hit.result))
        let watched = marks?.isWatched(hit) ?? false
        let onWatchlist = model.watchlistFilm.map { watchlist?.contains(tmdbID: $0.tmdbID) ?? false } ?? false
        let badge: WatchBadge = watched ? .watched : .none
        let decor = PosterDecor(owned: model.owned != nil, cam: model.isCAM,
                                onWatchlist: onWatchlist, dimsWatched: true)
        return PosterTile(model: model, state: PosterTileState(badge: badge, decor: decor),
                          actions: .make(kind: hit.kind, owned: model.owned != nil, watched: watched, onWatchlist: onWatchlist),
                          perform: performer.perform)
    }

    private var failedState: some View {
        VStack(spacing: 12) {
            Text("Couldn\u{2019}t load these titles.")
                .font(Theme.Typo.headline())
                .foregroundStyle(Theme.Palette.textPrimary)
            Button("Try Again") { Task { await store.loadSegment(store.selectedSegment) } }
                .buttonStyle(GlassButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
