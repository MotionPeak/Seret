import DebridCore
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
            case .movies:   browse("Movies", store.movies, store)
            case .shows:    browse("Shows", store.shows, store)
            case .settings: SettingsView()
            }
        }
    }

    @ViewBuilder
    private func browse(_ title: String, _ items: [MediaItem], _ store: LibraryStore) -> some View {
        NavigationStack {
            LibraryScreen(title: title, items: items, state: store.state, onRetry: { store.retry() })
                .navigationDestination(for: MediaItem.self) { item in
                    if let details = session.detailsProvider {
                        DetailView(item: item, details: details, watch: session.watchStore)
                    }
                }
                .navigationDestination(for: PlaybackRequest.self) { request in
                    if let (model, engine) = session.makePlayer(for: request) {
                        PlayerView(model: model, engine: engine,
                                   backdropURL: TMDBClient.imageURL(path: request.item.backdropPath, size: "original"))
                    } else {
                        PlaybackUnavailableView()
                    }
                }
        }
    }
}

/// Shown only if a player can't be built while signed in (e.g. the SwiftData container failed).
/// Gives the user a way back instead of a soft-locked blank screen.
private struct PlaybackUnavailableView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 54))
            Text("Unable to start playback.").font(.title2)
            Button("Back") { dismiss() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand { dismiss() }
    }
}
