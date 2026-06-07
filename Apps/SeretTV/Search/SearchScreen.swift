import DebridCore
import DebridUI
import SwiftUI

/// The Search tab: a `.searchable` field over the shared `SearchStore`, debounced, with a
/// results grid of poster tiles. Tapping a result pushes the Add screen (value-nav on the
/// shell's `SearchHit` destination).
struct SearchScreen: View {
    @Environment(AppSession.self) private var session
    @State private var query = ""

    var body: some View {
        Group {
            if let store = session.searchStore {
                content(store)
                    .searchable(text: $query, placement: .automatic,
                                prompt: "Search movies & shows")
                    .task(id: query) {
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled else { return }
                        await store.search(query: query)
                    }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func content(_ store: SearchStore) -> some View {
        switch store.state {
        case .idle:
            DiscoverRowsView()
        case .searching:
            ProgressView("Searching…").font(.title3)
        case .empty:
            message("No results for “\(query)”.", systemImage: "magnifyingglass")
        case .failed(let msg):
            message(msg, systemImage: "exclamationmark.triangle")
        case .results:
            SearchResultsGrid(hits: store.results)
        }
    }

    private func message(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 28) {
            Image(systemName: systemImage).font(.system(size: 64)).foregroundStyle(.secondary)
            Text(text).font(.title3).multilineTextAlignment(.center).frame(maxWidth: 700)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The idle Search page: browse rows (Recently Released + genres) from `DiscoverStore`.
/// Falls back to a prompt if discovery fails (e.g. offline).
private struct DiscoverRowsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            if let store = session.discoverStore {
                switch store.state {
                case .idle, .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed:
                    VStack(spacing: 28) {
                        Image(systemName: "magnifyingglass").font(.system(size: 64)).foregroundStyle(.secondary)
                        Text("Search for a movie or show to add.").font(.title3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .loaded:
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 40) {
                            ForEach(store.rows) { row in
                                VStack(alignment: .leading, spacing: 16) {
                                    Text(row.title).font(.title2.bold()).padding(.leading, 60)
                                    ScrollView(.horizontal) {
                                        LazyHStack(spacing: 40) {
                                            ForEach(row.hits) { SearchPosterCard(hit: $0) }
                                        }
                                        .padding(.horizontal, 60)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 40)
                    }
                }
            }
        }
        .task { await session.discoverStore?.load() }
    }
}

/// Scrolling grid of search-result poster tiles.
private struct SearchResultsGrid: View {
    let hits: [SearchHit]
    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 50)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 50) {
                ForEach(hits) { SearchPosterCard(hit: $0) }
            }
            .padding(60)
        }
    }
}

/// One focusable search-result tile — poster as the `.card`, title + kind below.
private struct SearchPosterCard: View {
    let hit: SearchHit
    private let width: CGFloat = 220
    private let height: CGFloat = 330

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: hit) { poster }
                .buttonStyle(.card)
            Text(hit.result.displayTitle)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }

    @ViewBuilder private var poster: some View {
        if let url = TMDBClient.imageURL(path: hit.result.posterPath, size: "w500") {
            AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                placeholder: { ZStack { Rectangle().fill(.gray.opacity(0.18)); ProgressView() } }
                .frame(width: width, height: height)
                .clipped()
        } else {
            Rectangle().fill(.gray.opacity(0.3))
                .overlay { Text(hit.result.displayTitle).font(.headline)
                    .multilineTextAlignment(.center).padding(12) }
                .frame(width: width, height: height)
        }
    }
}
