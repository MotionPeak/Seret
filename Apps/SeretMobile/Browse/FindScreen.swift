import DebridCore
import DebridUI
import SwiftUI

/// The Search page, on the glass language: a glass search field on top, Movies / Shows glass pills
/// under it, then the selected kind's Discover rails (with the For You / Trending / New / Popular /
/// Top Rated pills) while the field is empty, or a poster grid of results while typing. Pushed from
/// the glass Search circle on Home / Movies / Shows on iPhone (the system bar keeps its back
/// button); the iPad sidebar's Search row shows it as a root page with the glass page header.
///
/// Every poster opens the title's page (`HitTile`). The keyboard goes away on any drag, and never
/// comes back on its own after a title page closes (audit #5 — fixed on main; kept as it was).
struct FindScreen: View {
    @State private var kind: MediaKind

    init(kind: MediaKind = .movie) {
        _kind = State(initialValue: kind)
    }

    @Environment(AppSession.self) private var session
    /// Changes with what For You is seeded from — the library loading or changing, the profile
    /// resolving. See the segment load task.
    private var seedSignature: String {
        let size = (session.libraryStore?.movies.count ?? 0) + (session.libraryStore?.shows.count ?? 0)
        return "\(size)-\(session.activeProfileID ?? "")"
    }
    @Environment(AppRouter.self) private var router
    /// OPTIONAL, deliberately. A non-optional `@Environment` read of an `@Observable` TRAPS when
    /// the object is not in the environment, and it does not reliably cross a presentation
    /// boundary — which is the `EnvironmentValues.subscript.getter → assertionFailure` SIGTRAP in
    /// this app's crash reports. Absent marks must mean "no ticks yet", never a dead process.
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var query = ""
    /// Owned so the keyboard can be put away: scrolling never dismissed it, and closing a title
    /// page handed focus straight back to the field, so the keyboard returned and hid the tab bar.
    @FocusState private var searchFocused: Bool
    /// Set the first time the search page puts the keyboard up.
    @State private var didAutoFocus = false
    /// A title awaiting removal confirmation, and the failure to surface if RD refuses.
    @State private var pendingRemoval: MediaItem?
    @State private var removeErrorMessage: String?

#if DEBUG
    @Environment(\.uiPreviewStores) private var preview
    private var browse: DiscoverStore? {
        (kind == .movie ? preview?.moviesBrowse : preview?.showsBrowse)
            ?? (kind == .movie ? session.moviesBrowse : session.showsBrowse)
    }
    private var searchStore: SearchStore? { preview?.search ?? session.searchStore }
#else
    private var browse: DiscoverStore? { kind == .movie ? session.moviesBrowse : session.showsBrowse }
    private var searchStore: SearchStore? { session.searchStore }
#endif

    private var columns: [GridItem] { PosterTileMetrics.gridColumns(hSize) }

    var body: some View { searchPage }

    private var searchPage: some View {
        ZStack {
            CanvasBackground()
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                searchField
                kindFilter
                if let search = searchStore {
                    content(search)
                        // Keyed on kind TOO, so switching Movies/Shows re-runs the search for the new kind.
                        .task(id: "\(kind.rawValue)/\(query)") {
                            try? await Task.sleep(for: .milliseconds(350))
                            guard !Task.isCancelled else { return }
                            await search.search(query: query, kind: kind)
                        }
                } else {
                    skeleton
                }
            }
            .padding(.top, Theme.Space.sm)
        }
        // Arriving on Search means wanting to type. Once only: a page closing over this one must
        // not hand the field the keyboard again (see `searchFocused`).
        .onAppear {
            guard !didAutoFocus else { return }
            didAutoFocus = true
#if DEBUG
            if let seeded = preview?.searchQuery {
                query = seeded
                return
            }
#endif
            searchFocused = true
        }
        // Dragging the results or the rails puts the keyboard away, as every other search does.
        .scrollDismissesKeyboard(.immediately)
        // Opening a title — from a tile here or from anywhere else — gives up the field, so the
        // keyboard does not come back when the page closes.
        .onChange(of: router.detail == nil) { _, closed in if !closed { searchFocused = false } }
        .modifier(SearchPageBar(root: hSize == .regular))
        .libraryRemovalConfirmation(pending: $pendingRemoval,
                                    errorMessage: $removeErrorMessage,
                                    store: session.libraryStore)
    }

    /// Movies / Shows — the genre grid's glass sort pills.
    private var kindFilter: some View {
        HStack(spacing: Theme.Space.sm) {
            ForEach([MediaKind.movie, .show], id: \.self) { k in
                let selected = kind == k
                Button(k == .movie ? "Movies" : "Shows") { kind = k }
                    .buttonStyle(SortPillStyle(selected: selected))
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, PosterTileMetrics.margin(hSize))
    }

    private var searchField: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
            TextField("", text: $query,
                      prompt: Text(kind == .movie ? "Search movies" : "Search shows")
                          .foregroundStyle(Theme.Palette.textTertiary))
                .font(.system(size: 17, weight: .medium))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .foregroundStyle(Theme.Palette.textPrimary)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityLabel(kind == .movie ? "Search movies" : "Search shows")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.vertical, 13).padding(.horizontal, Theme.Space.lg)
        .contentShape(Capsule())
        .onTapGesture { searchFocused = true }
        .seretGlass(in: Capsule())
        .padding(.horizontal, PosterTileMetrics.margin(hSize))
    }

    @ViewBuilder private func content(_ search: SearchStore) -> some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            rails
        } else {
            switch search.state {
            case .idle, .searching:
                gridSkeleton
            case .empty:
                message("No results", systemImage: "magnifyingglass",
                        detail: "Nothing on TMDB matches \u{201C}\(query)\u{201D}.")
            case .failed(let msg):
                message("Search failed", systemImage: "exclamationmark.triangle", detail: msg)
            case .results:
                resultsGrid(search.results)
            }
        }
    }

    private var rails: some View {
        Group {
            if let browse {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    segmentPicker(browse)
                    segmentContent(browse)
                }
                // Keyed on kind AND segment so a Movies→Shows flip re-fires the load even when both
                // stores sit on the same segment (else the id wouldn't change and the new kind's rails
                // would stay stuck on the spinner).
                .task(id: "\(kind.rawValue)/\(browse.selectedSegment.rawValue)") {
                    await browse.loadSegment(browse.selectedSegment)
                }
                // A For You built before the library or the profile landed is rebuilt — quietly —
                // when they do; on the change only, never merely because the screen reappeared.
                .onChange(of: seedSignature) { _, _ in
                    Task { await browse.refreshForYouIfBetterSeeds() }
                }
                // Warm the first screenful of rail posters as rails land (the id re-fires per new
                // rail). First few rails only — prefetching a whole segment is cellular-hostile.
                .task(id: "prefetch-\(kind.rawValue)-\(browse.selectedSegment.rawValue)-\(browse.rows.count)") {
                    ImageMemoryCache.prefetch(browse.rows.prefix(3).flatMap(\.hits).compactMap {
                        TMDBClient.imageURL(path: $0.result.posterPath, size: "w342")
                    })
                }
            }
        }
    }

    @ViewBuilder private func segmentContent(_ browse: DiscoverStore) -> some View {
        switch browse.segmentState(browse.selectedSegment) {
        case .idle, .loading:
            skeleton
        case .failed:
            message("Couldn't load", systemImage: "exclamationmark.triangle",
                    detail: "Check your connection and try another section.")
        case .loaded:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(browse.rows) { row in
                        PosterRail(title: row.title) {
                            ForEach(row.hits) { tile($0, width: PosterTileMetrics.width(hSize), titled: false) }
                        }
                    }
                }
                .padding(.top, Theme.Space.sm)
                .padding(.bottom, Theme.Space.xxxl)
            }
            // One batched read across the visible rails; already-known titles cost nothing.
            .task(id: "marks-\(browse.rows.count)") {
                await marks?.load(browse.rows.flatMap(\.hits))
            }
        }
    }

    /// For You / Trending / New / Popular / Top Rated — glass pills, switching instantly.
    private func segmentPicker(_ browse: DiscoverStore) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                ForEach(DiscoverStore.Segment.allCases) { segment in
                    let selected = browse.selectedSegment == segment
                    Button(segment.title) { browse.select(segment) }
                        .buttonStyle(SortPillStyle(selected: selected))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
        .contentMargins(.horizontal, PosterTileMetrics.margin(hSize), for: .scrollContent)
    }

    /// CAM-likely (theatrical-window) — tagged in every row it appears in, not just In Theatres.
    private func isCAM(_ hit: SearchHit) -> Bool { browse?.isCAM(hit.result) ?? false }

    private func resultsGrid(_ hits: [SearchHit]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: PosterTileMetrics.spacing + 6) {
                ForEach(hits) { tile($0, width: nil, titled: true) }
            }
            .padding(.horizontal, PosterTileMetrics.margin(hSize))
            .padding(.top, Theme.Space.sm)
            .padding(.bottom, Theme.Space.xxxl)
        }
        // One batched read for whatever this search turned up, so the posters can say what you
        // have already seen.
        .task(id: hits.map(\.id).joined()) { await marks?.load(hits) }
    }

    private func tile(_ hit: SearchHit, width: CGFloat?, titled: Bool) -> some View {
        HitTile(hit: hit, width: width, cam: isCAM(hit), showsTitle: titled,
                onOpen: { searchFocused = false }, onRemove: { pendingRemoval = $0 })
    }

    /// Loading rails at the real rail metrics.
    private var skeleton: some View {
        ScrollView { RailSkeleton(rows: 3).padding(.top, Theme.Space.sm) }
            .scrollDisabled(true)
    }

    /// Loading results at the grid's own metrics.
    private var gridSkeleton: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: PosterTileMetrics.spacing + 6) {
                ForEach(0..<9, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: PosterTileMetrics.corner, style: .continuous)
                        .fill(Theme.Palette.surface1)
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                }
            }
            .padding(.horizontal, PosterTileMetrics.margin(hSize))
            .padding(.top, Theme.Space.sm)
        }
        .scrollDisabled(true)
        .accessibilityHidden(true)
    }

    private func message(_ title: String, systemImage: String, detail: String) -> some View {
        ScrollView {
            GlassMessageCard(systemImage: systemImage, title: title, text: detail, topPadding: 40) {
                EmptyView()
            }
        }
    }
}

/// Search's bar. Pushed on iPhone it keeps the system bar (glass on iOS 26) with its back button and
/// an inline title; as the iPad sidebar's root page it gets the same glass page header as the
/// other root pages.
private struct SearchPageBar: ViewModifier {
    let root: Bool

    func body(content: Content) -> some View {
        if root {
            content.glassPageHeader("Search") { EmptyView() }
        } else {
            content
                .navigationTitle("Search")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
