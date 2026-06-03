import SwiftUI

/// The signed-in root: a tvOS sidebar (Movies · Shows · Settings) over the library store.
struct LibraryShell: View {
    @Environment(AppSession.self) private var session
    @State private var selection: Section = .movies

    enum Section: Hashable { case movies, shows, settings }

    var body: some View {
        NavigationSplitView {
            List {
                Button { selection = .movies } label: {
                    Label("Movies", systemImage: "film")
                }
                Button { selection = .shows } label: {
                    Label("Shows", systemImage: "tv")
                }
                Button { selection = .settings } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .navigationTitle("Seret")
        } detail: {
            detail
        }
        // Loads once on appear; re-runs when the store's `retry()` bumps `attempt`.
        .task(id: session.libraryStore?.attempt ?? -1) {
            await session.libraryStore?.load()
        }
    }

    @ViewBuilder private var detail: some View {
        if let store = session.libraryStore {
            switch selection {
            case .movies:
                LibraryScreen(title: "Movies", items: store.movies,
                              state: store.state, onRetry: { store.retry() })
            case .shows:
                LibraryScreen(title: "Shows", items: store.shows,
                              state: store.state, onRetry: { store.retry() })
            case .settings:
                SettingsView()
            }
        }
    }
}
