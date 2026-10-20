import DebridCore
import DebridUI
import SwiftUI

/// Full-screen search, pushed from the Browse "Search" button. It owns the keyboard, so search only
/// opens when explicitly chosen — navigating the discover rows never triggers it. Results reuse the
/// shared `BrowseTile`, so tapping one pushes Detail (owned) or the Add flow (new) on the shell stack.
/// The focused result's ultrablur sits behind it all (`GridBackdrop`).
struct SearchScreen: View {
    /// The kind the side menu guessed from the section you were in — a starting point, not a
    /// constraint. Without the in-place toggle below, searching for a show from Home is a dead end.
    let initialKind: MediaKind

    @Environment(AppSession.self) private var session
    /// OPTIONAL, deliberately. A non-optional `@Environment` read of an `@Observable` TRAPS when
    /// the object is not in the environment, and it does not reliably cross a presentation
    /// boundary — which is the `EnvironmentValues.subscript.getter → assertionFailure` SIGTRAP in
    /// this app's crash reports. Absent marks must mean "no ticks yet", never a dead process.
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?
    @State private var query = ""
    @State private var kind: MediaKind
    @FocusState private var focusedKind: MediaKind?
    /// The backdrop's subject: results report focus, it publishes the one focus settles on. Only
    /// the backdrop reads it, so a move across the results never re-renders this screen.
    @State private var preview = FocusPreviewModel()

    init(kind: MediaKind) {
        self.initialKind = kind
        _kind = State(initialValue: kind)
    }

#if DEBUG
    /// `-uiPreview search`: a fixture store, the harness's art, and a query already typed.
    private var previewSearch: SearchStore?
    private var previewArt: TitleArtStore?

    init(kind: MediaKind, previewSearch: SearchStore, previewArt: TitleArtStore?, query: String) {
        self.init(kind: kind)
        self.previewSearch = previewSearch
        self.previewArt = previewArt
        _query = State(initialValue: query)
    }

    private var searchStore: SearchStore? { previewSearch ?? session.searchStore }
    private var art: TitleArtStore? { previewArt ?? session.titleArt }
#else
    private var searchStore: SearchStore? { session.searchStore }
    private var art: TitleArtStore? { session.titleArt }
#endif

    var body: some View {
        Group {
            if let search = searchStore {
                VStack(alignment: .leading, spacing: 0) {
                    kindToggle
                    content(search)
                }
                .searchable(text: $query, placement: .automatic,
                            prompt: kind == .movie ? "Search movies" : "Search shows")
                // Keyed on kind TOO, so flipping Movies/Shows re-runs the search in place instead
                // of leaving the previous kind's results on screen.
                .task(id: "\(kind.rawValue)/\(query)") {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    await search.search(query: query, kind: kind)
                }
            } else {
                SeretLoader()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { GridBackdrop(preview: preview, art: art) }
    }

    /// Movies / TV Shows in place. Commit-on-press like every other pill row in the app — and the
    /// same words and rhythm as My Library's, which said "TV Shows" at 24pt while this said
    /// "Shows" at 16pt. One control should not change its name between two screens.
    private var kindToggle: some View {
        HStack(spacing: 24) {
            Button("Movies") { kind = .movie }
                .buttonStyle(SeretPillStyle(selected: kind == .movie))
                .focused($focusedKind, equals: .movie)
            Button("TV Shows") { kind = .show }
                .buttonStyle(SeretPillStyle(selected: kind == .show))
                .focused($focusedKind, equals: .show)
        }
        .padding(.horizontal, Theme.Layout.contentMargin)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    @ViewBuilder private func content(_ search: SearchStore) -> some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            prompt
        } else {
            switch search.state {
            case .idle, .searching:
                SeretLoader(label: "Searching…")
            case .empty:
                message("No results.", systemImage: "magnifyingglass")
            case .failed(let msg):
                message(msg, systemImage: "exclamationmark.triangle")
            case .results:
                resultsGrid(search.results)
            }
        }
    }

    private var prompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass").font(.system(size: 72))
                .foregroundStyle(Theme.Palette.textSecondary)
            Text(kind == .movie ? "Search for a movie" : "Search for a show")
                .sectionTitle().foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultsGrid(_ hits: [SearchHit]) -> some View {
        let preview = preview
        return ScrollView {
            LazyVGrid(columns: PosterGridLayout.columns, spacing: PosterGridLayout.rowSpacing) {
                ForEach(hits) { hit in
                    CaptionedPoster(caption: hit.result.displayTitle) {
                        BrowseTile(hit: hit, onFocus: { preview.focus(PreviewSubject(hit: hit)) })
                    }
                }
            }
            .padding(.horizontal, Theme.Layout.contentMargin)
            .padding(.vertical, PosterGridLayout.topPadding)
        }
        .gridTopFade()
        // A new search shows its best result until focus picks one.
        .seedsGridBackdrop(preview, key: hits.first?.id ?? "",
                           first: hits.first.map(PreviewSubject.init(hit:)),
                           contains: { id in hits.contains { $0.id == id } })
        // One batched read for whatever this search turned up, so the posters can say what you
        // have already seen.
        .task(id: hits.map(\.id).joined()) { await marks?.load(hits) }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private func message(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 28) {
            Image(systemName: systemImage).font(.system(size: 64)).foregroundStyle(Theme.Palette.textSecondary)
            Text(text).sectionTitle().multilineTextAlignment(.center).frame(maxWidth: 700)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
