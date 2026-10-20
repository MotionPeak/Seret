import DebridCore
import DebridUI
import SwiftUI

/// A browse page (Movies or Shows), reached from the side menu — Plex/Netflix-style, like Home: a
/// focus-driven preview header (logo, metadata, synopsis over the ultrablur backdrop of the
/// focused title) above ONE stack of rows (`DiscoverStore.browseRows`): up to three For You rows,
/// Trending This Week, New This Month, Top Rated of All Time, then a row per genre ("Drama",
/// "Fantasy", "Sci-Fi"…). No segment pills, no genre strip.
///
/// - The header follows focus along the rows. Until a tile has had focus it shows the first title
///   of the first row, and follows it while the rows arrive (or For You is rebuilt above them).
/// - Each genre row ends in a "See All" tile that PUSHES that genre's full grid
///   (`GenreGridScreen`); Menu pops back to the same tile.
/// - Search lives in the side menu and is a SEPARATE full-screen screen, so navigating these rows
///   never pops the keyboard. Owned titles get a ✓; every title pushes its page. (Destinations are
///   registered by the shell.)
struct BrowseScreen: View {
    let kind: MediaKind

    @Environment(AppSession.self) private var session
    /// Changes with what For You is seeded from — the library loading or changing, the profile
    /// resolving. See the For You refresh below.
    private var seedSignature: String {
        let size = (session.libraryStore?.movies.count ?? 0) + (session.libraryStore?.shows.count ?? 0)
        return "\(size)-\(session.activeProfileID ?? "")"
    }
    /// OPTIONAL, deliberately. A non-optional `@Environment` read of an `@Observable` TRAPS when
    /// the object is not in the environment, and it does not reliably cross a presentation
    /// boundary — which is the `EnvironmentValues.subscript.getter → assertionFailure` SIGTRAP in
    /// this app's crash reports. Absent marks must mean "no ticks yet", never a dead process.
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?
    /// False while this is a kept-alive page behind another one (the shell disables it).
    @Environment(\.isEnabled) private var isVisiblePage
    /// The launch preload's backstop: past this, the page loads even if Home never answers (no
    /// profile, no library) — see `mayLoad`.
    @State private var preloadDeadlinePassed = false

    /// Drives the preview header: tiles report focus, it publishes the one focus settles on.
    @State private var preview = FocusPreviewModel()
    /// A Retry press is reloading the page. The failed row stays up — saying "Trying…" — until the
    /// load answers, so the focused Retry is never swapped for the skeleton under the viewer.
    @State private var retrying = false
    /// The page's focus, followed without a `FocusState` of this screen's own — that re-rendered
    /// the screen, and rebuilt every rail, on each move along a rail (measured on Home).
    @State var focusHandle = FocusBrowseHandle()
    /// What every focus move writes. Not observed: nothing in it is drawn.
    @State var focusMemory = BrowseFocusMemory()
    /// Where focus was when it last left the page (the side menu, a pushed title or genre):
    /// coming back in lands there. Written once per departure, not per move.
    @State var entryFocus: String?

#if DEBUG
    /// The store the `-uiPreview browse` harness renders instead of the session's — fixture rows
    /// that arrive progressively, without a TMDB key or a signed-in session.
    var previewBrowse: DiscoverStore?
    /// The harness's art store (the unsigned preview session has none).
    var previewArt: TitleArtStore?
    private var browse: DiscoverStore? {
        previewBrowse ?? (kind == .movie ? session.moviesBrowse : session.showsBrowse)
    }
    private var art: TitleArtStore? { previewArt ?? session.titleArt }
#else
    private var browse: DiscoverStore? { kind == .movie ? session.moviesBrowse : session.showsBrowse }
    private var art: TitleArtStore? { session.titleArt }
#endif

    var body: some View {
        ZStack {
            CanvasBackground()
            if let browse {
                content(browse)
            } else {
                SeretLoader()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Home has answered its first build — or there is no Home to wait for.
    private var homeHasAnswered: Bool { session.home.map(\.hasBuiltForProfile) ?? true }

    /// Whether the page may load. Both browse pages are built at launch, kept alive behind Home,
    /// and each is ~20 TMDB rows — so they wait for Home's first paint rather than compete with it
    /// (the preload stays; it only starts later). On screen, it loads at once.
    private var mayLoad: Bool { isVisiblePage || homeHasAnswered || preloadDeadlinePassed }

    private func content(_ browse: DiscoverStore) -> some View {
        page(browse)
            // Keyed on kind (a store for the other kind re-asks) and on `mayLoad`. The store owns
            // the load; this only asks (and joins one already running) — a return to the page
            // asks a loaded page, which is a no-op.
            .task(id: "\(kind.rawValue)/\(mayLoad)") {
                guard mayLoad else { return }
                await browse.loadBrowsePage()
            }
            .task {
                try? await Task.sleep(for: .seconds(8))
                preloadDeadlinePassed = true
            }
            // A page that failed while kept alive (at launch, offline) is asked again when it is
            // shown — as a Retry, so its failed row stays up, saying "Trying…", until it answers.
            .onChange(of: isVisiblePage) { _, visible in
                if visible, browse.browseState == .failed { retry(browse) }
            }
            // A For You built before the library or the profile had landed is rebuilt — quietly,
            // only that block, in one step — when they do. On the CHANGE only: hanging it off the
            // load above put skeletons under the viewer on the way back to the page.
            .onChange(of: seedSignature) { _, _ in
                Task { await browse.refreshForYouIfBetterSeeds() }
            }
    }

    // MARK: - The Plex page

    /// Stable ids for the page's non-rail rows. Rail ids are the store's row ids (`trend-week`,
    /// `rec-603`, `genre-18`…), which never collide with these.
    enum PageRow {
        static let skeleton = "browse-skeleton"
        /// The failed row.
        static let failed = "browse-failed"
        /// The failed row's Retry — its `plexFocusID`.
        static let retry = "browse-retry"
    }

    private func page(_ browse: DiscoverStore) -> some View {
        let rows = browse.browseRows
        let state = browse.browseState
        // ONE value feeding ONE branch (Home's rule): a retry's loading keeps the failed row, so
        // the flip failed → loading never rebuilds the focused button.
        let pageFailed = state == .failed || (retrying && (state == .loading || state == .idle))
        let keys = focusKeys(rows, retry: pageFailed)
        // Where focus goes on the way in — and where tvOS re-homes it when the focused view is
        // rebuilt: back where it was while that is still on the page, else Retry on a failed
        // page, else the first poster. (Nothing loaded yet: nothing on the page takes focus.)
        // `lastFocused` is read, not observed: it is current whenever the body runs, and the body
        // runs when the rows change and when focus leaves (`entryFocus`).
        // A focused row that left the page (a For You row dropped by a rebuild) hands focus to the
        // row now in its place, not back to the top.
        let focusTarget = [focusMemory.lastFocused, entryFocus].compactMap { $0 }.first(where: keys.contains)
            ?? (pageFailed ? PageRow.retry : nil)
            ?? Self.firstTileID(ofRowAt: focusMemory.lastRowIndex, in: rows)
            ?? rows.first?.hits.first.map { Self.tileID(rows[0].id, $0) }
        // While the page has no title to preview — failed, or still loading — the header names
        // the page instead of standing empty.
        let placeholder = FocusPreviewPlaceholder(
            title: kind == .movie ? "Movies" : "Shows",
            hint: pageFailed ? "Check your connection and try again." : "Loading titles…")
        return FocusBrowsePage(preview: preview, art: art, initialFocus: focusTarget,
                               focusOnEntry: true, handle: focusHandle, placeholder: placeholder) {
            if pageFailed {
                failed(browse)
            } else if state == .loaded {
                ForEach(rows) { row in
                    let index = rows.firstIndex { $0.id == row.id } ?? 0
                    PlexRail(title: row.title, id: row.id) {
                        ForEach(row.hits) { hit in tile(hit, row: row.id, index: index, browse: browse) }
                        // Fixed for the row's life (a row's id fixes its genre), so this is never
                        // a branch swap inside the lazy row.
                        if let genre = row.genre { seeAll(genre, seed: row.hits, index: index) }
                    }
                    // One batched read per rail; already-known titles cost nothing.
                    .task(id: row.hits.map(\.id).joined()) { await marks?.load(row.hits) }
                }
            } else {
                // Its own row with its own id, beside — never inside — the rails' lazy rows, and at
                // the rails' real metrics, so the page does not change height when they land.
                BrowseSkeleton().id(PageRow.skeleton)
            }
        }
        // A retry lets go of its failed row only when the page has answered (see `failed`).
        .onChange(of: browse.browseState) { _, state in
            if retrying, state.hasAnswered { retrying = false }
        }
        // Until a tile has had focus, the header shows the page's first title — and follows it
        // while the rows arrive, or when For You is rebuilt above them. A page with no titles
        // (loading, or failed) clears it, so the placeholder shows and the backdrop goes back to
        // the canvas; the next titles then lead again.
        .onChange(of: rows.first?.hits.first?.id ?? "", initial: true) { _, _ in
            if let first = rows.first?.hits.first {
                guard !focusMemory.tileHasHadFocus else { return }
                preview.showImmediately(PreviewSubject(hit: first))
            } else {
                focusMemory.tileHasHadFocus = false
                preview.clear()
            }
        }
        .onAppear { focusHandle.onChange = { focusChanged($0) } }
    }

    private func tile(_ hit: SearchHit, row: String, index: Int, browse: DiscoverStore) -> some View {
        let memory = focusMemory, preview = preview
        return BrowseTile(hit: hit, cam: browse.isCAM(hit.result), onFocus: {
            memory.tileHasHadFocus = true
            memory.lastRowIndex = index
            preview.focus(PreviewSubject(hit: hit))
        })
        .plexFocusID(Self.tileID(row, hit))
    }

    /// A genre row's last tile: opens the genre's full grid, seeded with the row's titles (its
    /// first page). The header keeps the title last focused — the tile names its genre itself.
    private func seeAll(_ genre: DiscoverStore.Genre, seed: [SearchHit], index: Int) -> some View {
        let memory = focusMemory
        return SeeAllTile(title: genre.name, value: BrowseDestination.genre(kind, genre, seed: seed),
                          onFocus: { memory.lastRowIndex = index })
            .plexFocusID(Self.seeAllID(genre))
    }

    /// Reloads a failed page, keeping its failed row (and a focused Retry) up until it answers.
    private func retry(_ browse: DiscoverStore) {
        guard !retrying else { return }
        retrying = true
        Task {
            await browse.loadBrowsePage()
            // Only once the load has ANSWERED. `loadBrowsePage` can return while the page still
            // reads loading (it joined a load already under way); letting go then flipped the row
            // to the skeleton under the focused button. The state change in `page` lets go when
            // the answer does land.
            if browse.browseState.hasAnswered { retrying = false }
        }
    }

    private func failed(_ browse: DiscoverStore) -> some View {
        let trying = retrying
        return VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 54))
                .foregroundStyle(Theme.Palette.textSecondary)
            Text("Couldn't load.").sectionTitle()
            // The label changes; the button does not — it keeps focus while the retry runs.
            Button(trying ? "Trying…" : "Retry") { retry(browse) }
            .buttonStyle(SeretPillStyle(selected: false))
            .plexFocusID(PageRow.retry)
            .reportsPlexRailFocus()
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
        .focusSection()
        .plexBrowseRow(id: PageRow.failed)
    }
}

/// A genre row's last tile: the genre and "See All" on glass, at the rail's poster size, with the
/// same focus ring and lift as the posters beside it (`FocusCardStyle`). A `NavigationLink(value:)`
/// like them, so the shell's stack pushes the grid and Menu pops back to this tile.
private struct SeeAllTile: View {
    let title: String
    let value: BrowseDestination
    var onFocus: () -> Void = {}

    var body: some View {
        NavigationLink(value: value) {
            VStack(spacing: 18) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text(title)
                    .cardTitle()
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                Text("See All")
                    .calloutText()
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(20)
            .frame(width: PosterTileMetrics.width, height: PosterTileMetrics.height)
            .background(Theme.Palette.glass,
                        in: RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous))
        }
        .focusCardButtonStyle()
        .reportsPlexRailFocus(onFocus)
        .accessibilityLabel("See all \(title)")
    }
}

/// Loading state for the page — redacted rails at `PlexRail`'s real metrics, so the screen reads
/// as "filling in" rather than flashing black, and the first rail lands where its skeleton was.
/// Not focusable, and a plain stack — nothing lazy that real tiles could ever share ids with.
private struct BrowseSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: FocusBrowseLayout.railSpacing) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 24) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.Palette.surface2)
                        .frame(width: 300, height: 34)
                        .padding(.leading, FocusBrowseLayout.leadingInset)
                    HStack(spacing: 28) {
                        ForEach(0..<8, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous)
                                .fill(Theme.Palette.surface2)
                                .frame(width: PosterTileMetrics.width, height: PosterTileMetrics.height)
                        }
                    }
                    .padding(.leading, FocusBrowseLayout.leadingInset)
                }
                .padding(.vertical, FocusBrowseLayout.railVerticalPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}

private extension DiscoverStore.State {
    /// The page's load has finished, either way.
    var hasAnswered: Bool { self == .loaded || self == .failed }
}
