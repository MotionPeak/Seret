import DebridCore
import DebridUI
import SwiftUI

/// One genre's titles as a dense poster grid — a genre row's "See All" on Movies/Shows, PUSHED on
/// the shell's stack like a title page: full screen (the side menu hides), and Menu pops back to
/// the See All tile it was opened from. The genre's name heads it, over a sort control, over the
/// focused title's ultrablur wash (`GridBackdrop`).
struct GenreGridScreen: View {
    let kind: MediaKind
    let genre: DiscoverStore.Genre
    /// The opening row's titles — the Popular sort's page 1. Drawn from the first frame (before
    /// the store exists) and handed to the store, so the grid never starts on a skeleton and the
    /// first poster can be the page's default focus.
    var seed: [SearchHit] = []
#if DEBUG
    /// `-uiPreview browse`: the fixture's genre titles (the preview session builds no grid store).
    var previewBrowsing: GenreBrowsing?
    /// The harness's art store (the unsigned preview session has none).
    var previewArt: TitleArtStore?
    private var art: TitleArtStore? { previewArt ?? session.titleArt }
#else
    private var art: TitleArtStore? { session.titleArt }
#endif
    /// The backdrop's subject. Never read here (only the backdrop reads `shown`), so a move across
    /// the grid never re-renders this screen and its cells.
    @State private var preview = FocusPreviewModel()

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
    /// Whether the FIRST poster has focus — the page's default focus. Bound to that one cell only,
    /// so it changes when focus enters or leaves it, never on every move across the grid (a
    /// per-cell focus state here would re-render the screen and its cells on each move).
    /// (`prefersDefaultFocus(_:in:)` was tried first: measured, tvOS still opened on the pills.)
    @FocusState private var firstPosterFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(genre.name)
                .screenTitle()
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .padding(.leading, Theme.Layout.contentMargin)
                .padding(.bottom, 12)
            sortRow
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The page opens on the first poster, not the sort pills above it. The seed puts that
        // poster on screen in the first frame, so this needs no claim-after-load.
        .defaultFocus($firstPosterFocused, true)
        .background { GridBackdrop(preview: preview, art: art) }
        // Rebuild the store when the genre actually changes — each grid is a fresh drill-down, but
        // merely coming back to this one is not.
        .task(id: genre.tmdbID) {
            guard loadedGenreID != genre.tmdbID else { return }
            loadedGenreID = genre.tmdbID
#if DEBUG
            let s = previewBrowsing.map { GenreGridStore(kind: kind, genre: genre, browsing: $0, seed: seed) }
                ?? session.makeGenreGrid(kind: kind, genre: genre, seed: seed)
#else
            let s = session.makeGenreGrid(kind: kind, genre: genre, seed: seed)
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
        .padding(.leading, Theme.Layout.contentMargin)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    @ViewBuilder private var content: some View {
        // Until the store exists (its `.task` runs after the first frame) the seed stands in for
        // it — the same titles the seeded store then holds, so nothing is swapped under focus.
        switch store?.state ?? (seed.isEmpty ? .loading : .loaded) {
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
            grid(store?.hits ?? seed)
        }
    }

    private func grid(_ hits: [SearchHit]) -> some View {
        let preview = preview
        return ScrollView {
            LazyVGrid(columns: PosterGridLayout.columns, spacing: PosterGridLayout.rowSpacing) {
                ForEach(hits) { hit in
                    CaptionedPoster(caption: hit.result.displayTitle) {
                        BrowseTile(hit: hit, onFocus: { preview.focus(PreviewSubject(hit: hit)) })
                            .modifier(FirstPosterFocus(isFirst: hit.id == hits.first?.id,
                                                       focused: $firstPosterFocused))
                    }
                    .onAppear {
                        // Page in when the tail comes into view.
                        if hit == hits.last { Task { await store?.loadMore() } }
                    }
                }
            }
            .padding(.horizontal, Theme.Layout.contentMargin)
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

/// Binds the grid's first poster to the page's default-focus state; every other cell is left as is.
private struct FirstPosterFocus: ViewModifier {
    let isFirst: Bool
    let focused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if isFirst { content.focused(focused) } else { content }
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
        .padding(.horizontal, Theme.Layout.contentMargin)
        .padding(.vertical, PosterGridLayout.topPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }
}
