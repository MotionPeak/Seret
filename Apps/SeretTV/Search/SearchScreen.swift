import DebridCore
import DebridUI
import SwiftUI

/// Full-screen search, pushed from the Browse "Search" button. It owns the keyboard, so search only
/// opens when explicitly chosen — navigating the discover rows never triggers it. Results reuse the
/// shared `BrowseTile`, so tapping one pushes Detail (owned) or the Add flow (new) on the shell stack.
struct SearchScreen: View {
    let kind: MediaKind

    @Environment(AppSession.self) private var session
    @State private var query = ""

    var body: some View {
        Group {
            if let search = session.searchStore {
                content(search)
                    .searchable(text: $query, placement: .automatic,
                                prompt: kind == .movie ? "Search movies" : "Search shows")
                    .task(id: query) {
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled else { return }
                        await search.search(query: query, kind: kind)
                    }
            } else {
                SeretLoader()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanvasBackground())
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
        let columns = [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 50)]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 50) {
                ForEach(hits) { BrowseTile(hit: $0) }
            }
            .padding(Theme.Layout.contentMargin)
        }
    }

    private func message(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 28) {
            Image(systemName: systemImage).font(.system(size: 64)).foregroundStyle(Theme.Palette.textSecondary)
            Text(text).sectionTitle().multilineTextAlignment(.center).frame(maxWidth: 700)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
