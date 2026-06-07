import DebridCore
import DebridUI
import SwiftUI

/// A browse tab (Movies or TV): a gold-glass search field scoped to the kind, over the kind's
/// `DiscoverStore` rails when idle, search results when typing. Posters already in the library
/// get an "In Library" badge and open their library Detail; new titles open the Add flow.
struct BrowseScreen: View {
    let kind: MediaKind

    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var query = ""

    private var browse: DiscoverStore? { kind == .movie ? session.moviesBrowse : session.showsBrowse }
    private var title: String { kind == .movie ? "Movies" : "TV Shows" }

    private var columns: [GridItem] {
        let minW: CGFloat = hSize == .regular ? 158 : 110
        let maxW: CGFloat = hSize == .regular ? 220 : 170
        return [GridItem(.adaptive(minimum: minW, maximum: maxW), spacing: Theme.Space.lg)]
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(spacing: Theme.Space.md) {
                searchField
                if let search = session.searchStore {
                    content(search)
                        .task(id: query) {
                            try? await Task.sleep(for: .milliseconds(350))
                            guard !Task.isCancelled else { return }
                            await search.search(query: query, kind: kind)
                        }
                } else {
                    loadingView
                }
            }
            .padding(.top, Theme.Space.sm)
            // On iPad the detail column butts right up against the sidebar — give the content
            // breathing room from the rail. (No-op in the compact tab bar.)
            .padding(.leading, hSize == .regular ? Theme.Space.xl : 0)
        }
        .navigationTitle(title)
    }

    private var searchField: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.Palette.textSecondary)
            TextField(kind == .movie ? "Search movies" : "Search shows", text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .foregroundStyle(Theme.Palette.textPrimary)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
        .padding(.vertical, Theme.Space.md).padding(.horizontal, Theme.Space.lg)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
        .padding(.horizontal, Theme.Space.lg)
    }

    @ViewBuilder private func content(_ search: SearchStore) -> some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            rails
        } else {
            switch search.state {
            case .idle, .searching:
                loadingView
            case .empty:
                message("No results", systemImage: "magnifyingglass")
            case .failed(let msg):
                message(msg, systemImage: "exclamationmark.triangle")
            case .results:
                resultsGrid(search.results)
            }
        }
    }

    private var rails: some View {
        Group {
            if let browse {
                switch browse.state {
                case .idle, .loading:
                    loadingView
                case .failed:
                    message("Couldn't load \(title.lowercased())", systemImage: "exclamationmark.triangle")
                case .loaded:
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Theme.Space.xl) {
                            ForEach(browse.sections) { section in sectionView(section) }
                        }
                        .padding(.vertical, Theme.Space.md)
                    }
                }
            }
        }
        .task { await browse?.load() }
    }

    /// A single In-Theatres rail, or a titled section ("New Releases"/"Most Popular") with a
    /// rail per genre. CAM-flagged sections badge their posters.
    @ViewBuilder private func sectionView(_ section: DiscoverStore.Section) -> some View {
        if section.rows.count == 1, section.rows[0].title.isEmpty {
            Rail(title: section.title) {
                ForEach(section.rows[0].hits) { tile($0, width: 120, cam: section.isCAM || isCAM($0)) }
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text(section.title).font(Theme.Typo.title())
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .padding(.horizontal, Theme.Space.lg)
                ForEach(section.rows) { row in
                    Rail(title: row.title) {
                        ForEach(row.hits) { tile($0, width: 120, cam: section.isCAM || isCAM($0)) }
                    }
                }
            }
        }
    }

    /// CAM-likely (theatrical-window) — tagged in every row it appears in, not just In Theatres.
    private func isCAM(_ hit: SearchHit) -> Bool { browse?.isCAM(hit.result) ?? false }

    private func resultsGrid(_ hits: [SearchHit]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Space.xl) {
                ForEach(hits) { tile($0, width: nil, cam: isCAM($0)) }
            }
            .padding(Theme.Space.lg)
        }
    }

    /// A poster that opens the Add flow, or — if already owned — shows an "In Library" badge and
    /// opens the owned item's Detail instead. `cam` posters get a CAM tag (In Theatres section).
    private func tile(_ hit: SearchHit, width: CGFloat?, cam: Bool) -> some View {
        let owned = session.libraryStore?.ownedItem(tmdbID: hit.result.id)
        return Button {
            if let owned { router.detail = owned } else { router.addHit = hit }
        } label: {
            PosterCard(title: hit.result.displayTitle,
                       posterURL: TMDBClient.imageURL(path: hit.result.posterPath, size: "w342"),
                       width: width)
                .overlay(alignment: .topTrailing) {
                    if owned != nil { inLibraryBadge.padding(6) }
                }
                .overlay(alignment: .topLeading) {
                    if cam, owned == nil { camBadge.padding(6) }
                }
        }
        .pressable()
    }

    private var inLibraryBadge: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Color(hex: 0x1A1400), Theme.Palette.gold)
            .background(Circle().fill(.black.opacity(0.35)))
    }

    /// Marks a theatrical-window title — likely only a cam/telesync is cached.
    private var camBadge: some View {
        Text("CAM")
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.red.opacity(0.85), in: Capsule())
    }

    /// Centered loading spinner. Extracted so the result-builder switch cases that use it stay
    /// single-expression — multi-statement `Spacer(); ProgressView(); Spacer()` cases trip the
    /// type-checker into bogus inference errors.
    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView().tint(Theme.Palette.gold)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(_ text: String, systemImage: String) -> some View {
        VStack(spacing: Theme.Space.md) {
            Spacer()
            Image(systemName: systemImage).font(.system(size: 42)).foregroundStyle(Theme.Palette.gold)
            Text(text).font(Theme.Typo.headline()).foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
