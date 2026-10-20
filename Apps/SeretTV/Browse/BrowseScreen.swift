import DebridCore
import DebridUI
import SwiftUI

/// A browse page (Movies or Shows), reached from the side menu — Plex-style, like Home: a
/// focus-driven preview header (logo, metadata, synopsis over the ultrablur backdrop of the
/// focused title) above the page's scroll, whose first row is the controls — the genre strip and
/// the For You / Trending / New / Popular / Top Rated pills — and then the selected segment's
/// `DiscoverStore` rails of `BrowseTile`s.
///
/// - The header follows focus along the rails. On the controls it keeps the last title focused —
///   or, until a tile in this segment has had focus, the first title of the segment's first rail —
///   so it is never blank and never describes another segment's rails.
/// - A genre pill swaps in that genre's grid over the page (kept alive underneath, so coming back
///   finds the rails where they were). Menu, or "All", returns to the rails.
/// - Search lives in the side menu and is a SEPARATE full-screen screen, so navigating these rows
///   never pops the keyboard. Owned titles get a ✓ and push their library page; new titles push the
///   placeholder page. (Destinations are registered by the shell.)
struct BrowseScreen: View {
    let kind: MediaKind

    @Environment(AppSession.self) private var session
    /// Changes with what For You is seeded from — the library loading or changing, the profile
    /// resolving. See the segment load task.
    private var seedSignature: String {
        let size = (session.libraryStore?.movies.count ?? 0) + (session.libraryStore?.shows.count ?? 0)
        return "\(size)-\(session.activeProfileID ?? "")"
    }
    /// OPTIONAL, deliberately. A non-optional `@Environment` read of an `@Observable` TRAPS when
    /// the object is not in the environment, and it does not reliably cross a presentation
    /// boundary — which is the `EnvironmentValues.subscript.getter → assertionFailure` SIGTRAP in
    /// this app's crash reports. Absent marks must mean "no ticks yet", never a dead process.
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?
    /// nil = "All" (the segment rails). A genre swaps in that genre's grid.
    @State private var genre: DiscoverStore.Genre?
    /// False while this is a kept-alive page behind another one (the shell disables it) — a hidden
    /// page must not claim the Menu press.
    @Environment(\.isEnabled) private var isVisiblePage

    /// Drives the preview header: tiles report focus, it publishes the one focus settles on.
    @State private var preview = FocusPreviewModel()
    /// The genre grid's backdrop subject — its own, so the rails' header keeps its title under it.
    @State private var genrePreview = FocusPreviewModel()
    /// The segment a Retry press is reloading. Its failed row stays up — saying "Trying…" — until
    /// the load answers, so the focused Retry is never swapped for the skeleton under the viewer.
    @State private var retrying: DiscoverStore.Segment?
    /// The page's focus, followed without a `FocusState` of this screen's own — that re-rendered
    /// the screen, and rebuilt every rail, on each move along a rail (measured on Home).
    @State var focusHandle = FocusBrowseHandle()
    /// What every focus move writes. Not observed: nothing in it is drawn.
    @State var focusMemory = BrowseFocusMemory()
    /// Where focus was when it last left the page (the side menu, a pushed title, the genre grid):
    /// coming back in lands there. Written once per departure, not per move.
    @State var entryFocus: String?

#if DEBUG
    /// The store the `-uiPreview browse` harness renders instead of the session's — fixture rails
    /// that arrive progressively, without a TMDB key or a signed-in session.
    var previewBrowse: DiscoverStore?
    /// The harness's art store (the unsigned preview session has none).
    var previewArt: TitleArtStore?
    /// The harness's genre titles (the preview session builds no genre grid store).
    var previewGenres: GenreBrowsing?
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

    private func content(_ browse: DiscoverStore) -> some View {
        // The page stays alive under the genre grid — its scroll, its focus memory and its header
        // stay as they were, so Menu out of a genre comes back to the same place.
        page(browse)
            .opacity(genre == nil ? 1 : 0)
            .disabled(genre != nil)
            .accessibilityHidden(genre != nil)
            .overlay(alignment: .topLeading) {
                if let genre { genreLayer(genre) }
            }
        // Menu out of a genre returns to the rails rather than opening the side menu. Only while
        // a genre is up — and the shell stands its own handler down meanwhile (it won otherwise);
        // the rest of the time the shell's Menu (open the side menu) applies.
        .onExitCommand(perform: genre == nil ? nil : { self.genre = nil })
        // A new genre starts on the canvas: the old genre's wash must not sit behind the new
        // genre's skeletons. Its grid seeds the backdrop from its first title when they land.
        .onChange(of: genre?.tmdbID) { _, _ in genrePreview.clear() }
        .claimsMenuPress(genre != nil && isVisiblePage)
        // Load the selected segment whenever it changes (and on first show). Keyed on kind TOO,
        // so Find's Movies→Shows flip re-fires the load even when both stores sit on the same
        // segment (else the id wouldn't change and the new kind's rails would stay stuck loading).
        // The store owns the load; this only asks (and joins one already running).
        .task(id: "\(kind.rawValue)/\(browse.selectedSegment.rawValue)") {
            await browse.loadSegment(browse.selectedSegment)
        }
        // A For You built before the library or the profile had landed is rebuilt — quietly —
        // when they do. On the CHANGE only: a return to this page re-runs the task above, and
        // hanging the rebuild off that put skeletons under the viewer on the way back.
        .onChange(of: seedSignature) { _, _ in
            Task { await browse.refreshForYouIfBetterSeeds() }
        }
    }

    // MARK: - The Plex page

    /// Stable ids for the page's non-rail rows. Rail ids are the store's row ids (`trend-day`,
    /// `rec-603`…), which never collide with these.
    enum PageRow {
        static let controls = "browse-controls"
        static let skeleton = "browse-skeleton"
        /// The failed row's Retry — its `plexFocusID`.
        static let retry = "browse-retry"
    }

    private func page(_ browse: DiscoverStore) -> some View {
        let segment = browse.selectedSegment
        let rows = browse.rows
        let state = browse.segmentState(segment)
        // ONE value feeding ONE branch (Home's rule): a retry's loading keeps the failed row, so
        // the flip failed → loading never rebuilds the focused button.
        let segmentFailed = state == .failed
            || (retrying == segment && (state == .loading || state == .idle))
        let keys = focusKeys(rows, retry: segmentFailed)
        // Where focus goes on the way in — and where tvOS re-homes it when the focused view is
        // rebuilt (measured: a For You rebuild that inserts a rail above the focused one re-homed
        // focus to the page's default, the new first poster): back where it was while that is
        // still on the page, else the first poster, else — nothing loaded yet — the selected
        // segment's pill. `lastFocused` is read, not observed: it is current whenever the body
        // runs, and the body runs when the rails change and when focus leaves (`entryFocus`).
        // A failed segment's Retry comes before the first poster: re-homing after a failed reload
        // keeps Try Again focused rather than handing focus to a stale tile or the pills.
        let focusTarget = [focusMemory.lastFocused, entryFocus].compactMap { $0 }.first(where: keys.contains)
            ?? (segmentFailed ? PageRow.retry : nil)
            ?? rows.first?.hits.first.map { Self.tileID(rows[0].id, $0) }
            ?? Self.segmentID(segment)
        return FocusBrowsePage(preview: preview, art: art, initialFocus: focusTarget,
                               focusOnEntry: true, handle: focusHandle) {
            // A failed segment's message lives IN the controls row, under the pills: as a row of its
            // own, focusing Retry scrolled it to the top of the rail area and the pills up under
            // the top fade (measured in `-uiPreview browsefailed`).
            controls(browse, failed: segmentFailed ? segment : nil)
            if segmentFailed {
                // Nothing below the controls: the message is in them.
            } else if state == .loaded {
                ForEach(rows) { row in
                    PlexRail(title: row.title, id: row.id) {
                        ForEach(row.hits) { hit in tile(hit, row: row.id, segment: segment, browse: browse) }
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
        // A retry lets go of its failed row only when the segment has answered (see `failed`).
        .onChange(of: browse.segmentState(segment)) { _, state in
            if retrying == segment, state.hasAnswered { retrying = nil }
        }
        // A retry belongs to its segment: switching away drops it, so coming back finds the
        // segment as it is (and a live Retry) rather than a "Trying…" no load will ever clear.
        .onChange(of: segment) { _, _ in retrying = nil }
        // Until a tile of THIS segment has had focus, the header shows the segment's first title —
        // and follows it while the rails arrive, and when a segment switch brings in new ones.
        .onChange(of: headerKey(segment, rows), initial: true) { _, _ in
            guard focusMemory.headerSegment != segment,
                  let first = rows.first?.hits.first else { return }
            focusMemory.headerSegment = nil
            preview.showImmediately(PreviewSubject(hit: first))
        }
        .onAppear { focusHandle.onChange = { focusChanged($0) } }
    }

    /// The first row of the page's scroll: the genre strip over the segment pills. A
    /// `plexBrowseRow`, so moving up into it (or back down out of it into the first rail) moves the
    /// page like any rail does.
    private func controls(_ browse: DiscoverStore, failed failedSegment: DiscoverStore.Segment?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GenreStrip(kind: kind, selection: $genre)
            segmentPicker(browse)
            if let failedSegment { failed(browse, segment: failedSegment) }
        }
        .padding(.top, 12)
        // A rail's own room below, so with the first rail at the top nothing of the pills shows
        // above it (the rails' negative spacing overlaps exactly one such padding).
        .padding(.bottom, FocusBrowseLayout.railVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plexBrowseRow(id: PageRow.controls)
    }

    /// For You / Trending / New / Popular / Top Rated.
    /// Commit-on-press: moving focus across the pills only highlights them; a click switches the
    /// section — consistent with the side menu, so gliding the remote never reloads a rail set by
    /// accident. (`DiscoverStore` owns every segment's load, so a switch mid-load cannot strand one.)
    private func segmentPicker(_ browse: DiscoverStore) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(DiscoverStore.Segment.allCases) { seg in
                    Button(seg.title) { browse.select(seg) }
                        .buttonStyle(SeretPillStyle(selected: seg == browse.selectedSegment))
                        .plexFocusID(Self.segmentID(seg))
                        .reportsPlexRailFocus()
                }
            }
            .padding(.horizontal, FocusBrowseLayout.leadingInset)
            .padding(.vertical, 12)
        }
        .scrollClipDisabled()
        // The pill row is narrower than the edge-to-edge rails below it, so without a full-width
        // section a card scrolled to the right had nothing above it.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private func tile(_ hit: SearchHit, row: String, segment: DiscoverStore.Segment,
                      browse: DiscoverStore) -> some View {
        let memory = focusMemory, preview = preview
        return BrowseTile(hit: hit, cam: browse.isCAM(hit.result), onFocus: {
            memory.headerSegment = segment
            preview.focus(PreviewSubject(hit: hit))
        })
        .plexFocusID(Self.tileID(row, hit))
    }

    private func failed(_ browse: DiscoverStore, segment: DiscoverStore.Segment) -> some View {
        let trying = retrying == segment
        return VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 54))
                .foregroundStyle(Theme.Palette.textSecondary)
            Text("Couldn't load.").sectionTitle()
            // The label changes; the button does not — it keeps focus while the retry runs.
            Button(trying ? "Trying…" : "Retry") {
                guard !trying else { return }
                retrying = segment
                Task {
                    await browse.loadSegment(segment)
                    // Only once the load has ANSWERED. `loadSegment` can return while the segment
                    // still reads loading (it joined, or found, a load already under way); letting
                    // go then flipped the row to the skeleton under the focused button. The
                    // segment-state change below lets go when the answer does land.
                    if retrying == segment, browse.segmentState(segment).hasAnswered { retrying = nil }
                }
            }
            .buttonStyle(SeretPillStyle(selected: false))
            .plexFocusID(PageRow.retry)
            .reportsPlexRailFocus()
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
        .focusSection()
    }

    // MARK: - Genre grid

    /// The genre strip again, over that genre's grid, over the focused title's ultrablur. Its strip
    /// claims focus, so the page's focused pill — gone under it the moment the grid swaps in —
    /// hands focus to the same genre here rather than to the side menu. At the page's own inset,
    /// so the pills do not jump sideways when the grid swaps in.
    private func genreLayer(_ selected: DiscoverStore.Genre) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GenreStrip(kind: kind, selection: $genre, leadingInset: PosterGridLayout.rootInset,
                       claimsFocus: true)
                .padding(.bottom, 6)
            genreGrid(selected)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { GridBackdrop(preview: genrePreview, art: art) }
    }

    private func genreGrid(_ selected: DiscoverStore.Genre) -> some View {
#if DEBUG
        GenreGridScreen(kind: kind, genre: selected, preview: genrePreview, previewBrowsing: previewGenres)
#else
        GenreGridScreen(kind: kind, genre: selected, preview: genrePreview)
#endif
    }
}

/// Loading state for a browse segment — redacted rails at `PlexRail`'s real metrics, so the screen
/// reads as "filling in" rather than flashing black, and the first rail lands where its skeleton
/// was. Not focusable, and a plain stack — nothing lazy that real tiles could ever share ids with.
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
    /// The segment's load has finished, either way.
    var hasAnswered: Bool { self == .loaded || self == .failed }
}
