import DebridCore
import SwiftUI

/// The signed-in root: a tvOS top tab bar (Movies · Shows · Settings) over the library store.
/// The tab bar is the native Apple-TV navigation chrome — it labels the section and collapses
/// out of the way when focus moves into the grid, so there's no persistent side panel.
struct LibraryShell: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        TabView {
            Tab("Movies", systemImage: "film") {
                if let store = session.libraryStore { browse("Movies", store.movies, store) }
            }
            Tab("Shows", systemImage: "tv") {
                if let store = session.libraryStore { browse("Shows", store.shows, store) }
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        // Loads once on appear; re-runs when the store's `retry()` bumps `attempt`.
        .task(id: session.libraryStore?.attempt ?? -1) {
            await session.libraryStore?.load()
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
