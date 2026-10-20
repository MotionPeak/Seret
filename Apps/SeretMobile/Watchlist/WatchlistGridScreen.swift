import DebridCore
import DebridUI
import SwiftUI

/// One Watchlist row's films as a full poster grid — the row's "See All". Adaptive columns (about
/// three across an iPhone in portrait, more on iPad and in landscape), each poster captioned.
///
/// Built from the same model and details as the page (`WatchlistPageData`), not a copy taken at the
/// push: a film removed here leaves the grid and the page at once, and a row that fills in while
/// it is open (a genre, as details settle) grows here too.
struct WatchlistGridScreen: View {
    let route: WatchlistGridRoute
    let model: WatchlistModel
    let details: WatchlistDetailsStore?

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?
    @State private var pendingRemoval: WatchlistEntry?

    var body: some View {
        let data = WatchlistPageData(model: model, details: details)
        let row = data.rows.first { $0.id == route.rowID }
        let entries = row?.entries ?? []
        ZStack {
            CanvasBackground()
            if entries.isEmpty {
                // Its last film was removed (here, or by a sync while it was open).
                WatchlistMessageCard(systemImage: "bookmark", title: "Nothing here any more",
                                     text: "Every film in this row has left your watchlist.") {
                    EmptyView()
                }
            } else {
                ScrollView {
                    if let subtitle = row?.subtitle {
                        Text("\(entries.count) films · \(subtitle)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, PosterTileMetrics.margin(hSize))
                            .padding(.bottom, Theme.Space.sm)
                    }
                    LazyVGrid(columns: PosterTileMetrics.gridColumns(hSize),
                              spacing: PosterTileMetrics.spacing + 4) {
                        ForEach(entries) { entry in
                            WatchlistFilmTile(entry: entry,
                                              owned: data.showsOwnedMark(entry, in: row?.kind ?? .recent),
                                              badge: data.badge(for: entry), width: nil,
                                              showsTitle: true,
                                              onRemove: { pendingRemoval = $0 })
                        }
                    }
                    .padding(.horizontal, PosterTileMetrics.margin(hSize))
                    .padding(.bottom, Theme.Space.xxxl)
                }
                .task(id: entries.count) { await marks?.load(WatchlistFilmMarks.hits(entries)) }
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .watchlistRemovalDialog(pending: $pendingRemoval, model: model)
    }
}
