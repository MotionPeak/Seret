import DebridCore
import DebridUI
import SwiftUI

/// The signed-in root: a tvOS top tab bar (Movies · Shows · Settings) over the library store.
/// The tab bar is the native Apple-TV navigation chrome — it labels the section and collapses
/// out of the way when focus moves into the grid, so there's no persistent side panel.
struct LibraryShell: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        // One root NavigationStack OUTSIDE the TabView: drilling into Detail / the player pushes a
        // full-screen view that covers the tab bar (no menu-bar bleed at the top), and Menu pops
        // straight back to the grid instead of snagging on the tab bar.
        NavigationStack {
            TabView {
                Tab("Movies", systemImage: "film") { grid("Movies", \.movies) }
                Tab("Shows", systemImage: "tv") { grid("Shows", \.shows) }
                Tab("Settings", systemImage: "gearshape") { SettingsView() }
            }
            .navigationDestination(for: MediaItem.self) { item in
                if let details = session.detailsProvider {
                    DetailView(item: item, details: details, watch: session.watchStore)
                }
            }
            .navigationDestination(for: PlaybackRequest.self) { request in
                let engine = VLCKitVideoPlayerEngine()
                let thumbnails = ThumbnailProvider()
                if let model = session.makePlayer(
                    for: request, engine: engine,
                    fetchThumbnail: { url, fraction in await thumbnails.frame(url: url, fraction: fraction) }) {
                    PlayerView(model: model, engine: engine,
                               backdropURL: TMDBClient.imageURL(path: request.item.backdropPath, size: "original"))
                } else {
                    PlaybackUnavailableView()
                }
            }
        }
        // Loads once on appear; re-runs when the store's `retry()` bumps `attempt`.
        .task(id: session.libraryStore?.attempt ?? -1) {
            await session.libraryStore?.load()
        }
    }

    @ViewBuilder
    private func grid(_ title: String, _ items: KeyPath<LibraryStore, [MediaItem]>) -> some View {
        if let store = session.libraryStore {
            LibraryScreen(title: title, items: store[keyPath: items], state: store.state,
                          onRetry: { store.retry() })
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
