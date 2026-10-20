import DebridCore
import DebridUI
import SwiftUI

/// One genre's titles as a dense poster grid, with the old segment pills demoted to a sort control.
/// Its cells report focus to `preview`, which drives the backdrop its host draws behind the strip
/// and the grid together (see `BrowseScreen.genreLayer`).
struct GenreGridScreen: View {
    let kind: MediaKind
    let genre: DiscoverStore.Genre
    /// The host's backdrop subject. Never read here (only the backdrop reads `shown`), so a move
    /// across the grid re-renders neither this screen nor its host.
    let preview: FocusPreviewModel
#if DEBUG
    /// `-uiPreview browse`: the fixture's genre titles (the preview session builds no grid store).
    var previewBrowsing: GenreBrowsing?
#endif

    @Environment(AppSession.self) private var session
    /// OPTIONAL, deliberately. A non-optional `@Environment` read of an `@Observable` TRAPS when
    /// the object is not in the environment, and it does not reliably cross a presentation
    /// boundary — which is the `EnvironmentValues.subscript.getter → assertionFailure` SIGTRAP in
    /// this app's crash reports. Absent marks must mean "no ticks yet", never a dead process.
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?
    @State private var store: GenreGridStore?
    /// The genre `store` was built for. `.task(id:)` re-runs on every re-appearance, not only when
    /// the id changes — and coming back from a title is a re-appearance — so without this the grid
    /// threw away every page it had loaded and dropped the viewer back at the top of page 1.
    @State private var loadedGenreID: Int?
    @FocusState private var focusedSort: GenreSort?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sortRow
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Rebuild the store when the genre actually changes — each grid is a fresh drill-down, but
        // merely coming back to this one is not.
        .task(id: genre.tmdbID) {
            guard loadedGenreID != genre.tmdbID else { return }
            loadedGenreID = genre.tmdbID
#if DEBUG
            let s = previewBrowsing.map { GenreGridStore(kind: kind, genre: genre, browsing: $0) }
                ?? session.makeGenreGrid(kind: kind, genre: genre)
#else
            let s = session.makeGenreGrid(kind: kind, genre: genre)
#endif
            store = s
            await s?.load()
        }
    }

    private var sortRow: some View {
        HStack(spacing: 16) {
            ForEach(GenreSort.allCases) { sort in
                Button(sort.title) {
                    Task { await store?.select(sort: sort) }
                }
                .buttonStyle(SeretPillStyle(selected: store?.sort == sort))
                .focused($focusedSort, equals: sort)
            }
        }
        .padding(.leading, PosterGridLayout.rootInset)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    @ViewBuilder private var content: some View {
        switch store?.state ?? .loading {
        case .idle, .loading:
            // Fixed-height skeletons. A grid that goes empty→full under a ScrollView collapses its
            // height and snaps the page to the top — this app has hit that twice.
            GenreGridSkeleton()
        case .failed:
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 54))
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text("Nothing here.").sectionTitle()
                Button("Retry") { Task { await store?.load() } }
                    .buttonStyle(SeretPillStyle(selected: false))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            grid(store?.hits ?? [])
        }
    }

    private func grid(_ hits: [SearchHit]) -> some View {
        let preview = preview
        return ScrollView {
            LazyVGrid(columns: PosterGridLayout.columns, spacing: PosterGridLayout.rowSpacing) {
                ForEach(hits) { hit in
                    CaptionedPoster(caption: hit.result.displayTitle) {
                        BrowseTile(hit: hit, onFocus: { preview.focus(PreviewSubject(hit: hit)) })
                    }
                    .onAppear {
                        // Page in when the tail comes into view.
                        if hit == hits.last { Task { await store?.loadMore() } }
                    }
                }
            }
            .padding(.horizontal, PosterGridLayout.rootInset)
            .padding(.vertical, PosterGridLayout.topPadding)
        }
        .gridTopFade()
        // The genre's first title until focus picks one — and again for a new sort or genre.
        .seedsGridBackdrop(preview, key: hits.first?.id ?? "",
                           first: hits.first.map(PreviewSubject.init(hit:)),
                           contains: { id in hits.contains { $0.id == id } })
        .task(id: hits.map(\.id).joined()) { await marks?.load(hits) }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }
}

/// Redacted cells at the grid's real size — the 236×354 poster and its caption line, in the grid's
/// columns and insets — so the page height never changes while it loads. A plain grid outside the
/// real one (never a skeleton branch inside a lazy container).
private struct GenreGridSkeleton: View {
    var body: some View {
        LazyVGrid(columns: PosterGridLayout.columns, spacing: PosterGridLayout.rowSpacing) {
            ForEach(0..<12, id: \.self) { _ in
                VStack(alignment: .leading, spacing: PosterGridLayout.captionSpacing) {
                    RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous)
                        .fill(Theme.Palette.surface2)
                        .frame(width: PosterTileMetrics.width, height: PosterTileMetrics.height)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.Palette.surface2)
                        .frame(width: PosterTileMetrics.width * 0.6, height: 28)
                }
            }
        }
        .padding(.horizontal, PosterGridLayout.rootInset)
        .padding(.vertical, PosterGridLayout.topPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }
}
