import DebridCore
import DebridUI
import SwiftUI

/// The Search tab: a gold-glass search field over the shared `SearchStore`, debounced, with
/// an adaptive results grid. Tapping a result opens the Add screen (full-screen via `AppRouter`,
/// so it survives rotation — same pattern as Detail).
struct SearchScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var query = ""

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
                if let store = session.searchStore {
                    content(store)
                        .task(id: query) {
                            try? await Task.sleep(for: .milliseconds(350))
                            guard !Task.isCancelled else { return }
                            await store.search(query: query)
                        }
                } else {
                    Spacer()
                    ProgressView().tint(Theme.Palette.gold)
                    Spacer()
                }
            }
            .padding(.top, Theme.Space.sm)
        }
        .navigationTitle("Search")
    }

    private var searchField: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.Palette.textSecondary)
            TextField("Movies & shows", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
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

    @ViewBuilder private func content(_ store: SearchStore) -> some View {
        switch store.state {
        case .idle:
            message("Find something to add", systemImage: "magnifyingglass",
                    detail: "Search any movie or show and add the best cached version to Real‑Debrid.")
        case .searching:
            Spacer(); ProgressView().tint(Theme.Palette.gold); Spacer()
        case .empty:
            message("No results", systemImage: "magnifyingglass", detail: "Nothing matched “\(query)”.")
        case .failed(let msg):
            message("Search failed", systemImage: "exclamationmark.triangle", detail: msg)
        case .results:
            ScrollView {
                LazyVGrid(columns: columns, spacing: Theme.Space.xl) {
                    ForEach(store.results) { hit in
                        Button { router.addHit = hit } label: {
                            PosterCard(title: hit.result.displayTitle,
                                       posterURL: TMDBClient.imageURL(path: hit.result.posterPath, size: "w500"),
                                       width: nil)
                        }
                        .pressable()
                    }
                }
                .padding(Theme.Space.lg)
            }
        }
    }

    private func message(_ title: String, systemImage: String, detail: String) -> some View {
        VStack(spacing: Theme.Space.md) {
            Spacer()
            Image(systemName: systemImage).font(.system(size: 42)).foregroundStyle(Theme.Palette.gold)
            Text(title).font(Theme.Typo.headline()).foregroundStyle(Theme.Palette.textPrimary)
            Text(detail).font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, Theme.Space.xxl)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
