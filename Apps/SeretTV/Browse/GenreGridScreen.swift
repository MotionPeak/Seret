import DebridCore
import DebridUI
import SwiftUI

/// One genre's titles as a dense poster grid, with the old segment pills demoted to a sort control.
struct GenreGridScreen: View {
    let kind: MediaKind
    let genre: DiscoverStore.Genre

    @Environment(AppSession.self) private var session
    @State private var store: GenreGridStore?
    @FocusState private var focusedSort: GenreSort?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sortRow
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Rebuild the store when the genre changes — each grid is a fresh drill-down.
        .task(id: genre.tmdbID) {
            let s = session.makeGenreGrid(kind: kind, genre: genre)
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
        let columns = [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 50)]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 50) {
                ForEach(hits) { hit in
                    BrowseTile(hit: hit)
                        .onAppear {
                            // Page in when the tail comes into view.
                            if hit == hits.last { Task { await store?.loadMore() } }
                        }
                }
            }
            .padding(.horizontal, Theme.Layout.contentMargin)
            .padding(.vertical, 30)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }
}

/// Redacted posters at the grid's real size, so the page height never changes while it loads.
private struct GenreGridSkeleton: View {
    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 50)]
        return LazyVGrid(columns: columns, spacing: 50) {
            ForEach(0..<12, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous)
                    .fill(Theme.Palette.surface2)
                    .frame(height: 330)
            }
        }
        .padding(.horizontal, Theme.Layout.contentMargin)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
