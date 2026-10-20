import DebridCore
import DebridUI
import SwiftUI

/// One Watchlist row's films as a full poster grid — a row's "See All", PUSHED like a genre grid:
/// full screen (the side menu hides), the row's name over the grid, the focused film's ultrablur
/// wash behind it (`GridBackdrop`), and Menu pops back to the See All tile it was opened from.
///
/// Built from the same model and details as the page (`WatchlistPageData`), not from a copy taken
/// at the push: a film removed here leaves the grid and the page at once, and a row that fills in
/// while it is open (a genre, as details arrive) grows here too.
struct WatchlistGridScreen: View {
    let route: WatchlistGridRoute
    let model: WatchlistModel
    let details: WatchlistDetailsStore?
    let art: TitleArtStore?

    /// The backdrop's subject. Never read here (only the backdrop reads `shown`), so a move across
    /// the grid never re-renders this screen and its cells.
    @State private var preview = FocusPreviewModel()
    @State private var pendingRemoval: WatchlistEntry?
    /// Whether the FIRST poster has focus — the page's default focus, bound to that cell only.
    @FocusState private var firstPosterFocused: Bool

    var body: some View {
        let data = WatchlistPageData(model: model, details: details)
        let row = data.rows.first { $0.id == route.rowID }
        let entries = row?.entries ?? []
        VStack(alignment: .leading, spacing: 0) {
            Text(route.title)
                .screenTitle()
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .padding(.leading, Theme.Layout.contentMargin)
                .padding(.bottom, 12)
            if entries.isEmpty {
                // Its last film was removed (here, or by a sync while it was open).
                Text("Nothing here any more.")
                    .sectionTitle()
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                grid(entries, kind: row?.kind ?? .recent, data: data)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Opens on the first poster. The entries are on screen in the first frame (they come from
        // the page's own model), so this needs no claim-after-load.
        .defaultFocus($firstPosterFocused, true)
        .background { GridBackdrop(preview: preview, art: art) }
        .watchlistRemovalDialog(pending: $pendingRemoval, model: model)
    }

    private func grid(_ entries: [WatchlistEntry], kind: WatchlistRow.Kind,
                      data: WatchlistPageData) -> some View {
        let preview = preview, art = art
        let firstSlug = entries.first?.slug
        let subjects = entries.map { data.subject(for: $0) }
        let subjectIDs = Set(subjects.map(\.id))
        return ScrollView {
            LazyVGrid(columns: PosterGridLayout.columns, spacing: PosterGridLayout.rowSpacing) {
                ForEach(entries) { entry in
                    let matched = entry.tmdbID != nil
                    CaptionedPoster(caption: matched ? WatchlistName.stripYear(from: entry.name)
                                                     : "No TMDB match",
                                    note: !matched) {
                        WatchlistTile(entry: entry, owned: data.showsOwnedMark(entry, in: kind),
                                      badge: data.badge(for: entry),
                                      onRemove: { pendingRemoval = $0 },
                                      onFocus: {
                                          if let id = entry.tmdbID, let info = data.details[id] {
                                              art?.seed(info.titleArt, for: .movie, tmdbID: id)
                                          }
                                          preview.focus(data.subject(for: entry))
                                      })
                            .modifier(WatchlistFirstPoster(isFirst: entry.slug == firstSlug,
                                                           focused: $firstPosterFocused))
                    }
                }
            }
            .padding(.horizontal, Theme.Layout.contentMargin)
            .padding(.vertical, PosterGridLayout.topPadding)
        }
        .gridTopFade()
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        // The first film until focus picks one — and again when the one on the backdrop leaves.
        .seedsGridBackdrop(preview, key: subjects.map(\.id).joined(separator: "|"),
                           first: subjects.first,
                           contains: { subjectIDs.contains($0) })
    }
}

/// Binds the grid's first poster to the page's default-focus state; every other cell is left as is.
private struct WatchlistFirstPoster: ViewModifier {
    let isFirst: Bool
    let focused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if isFirst { content.focused(focused) } else { content }
    }
}
