import DebridCore
import DebridUI
import SwiftUI

/// The signed-in root: a tvOS top tab bar (Movies · TV · My Library · Settings). Movies/TV are
/// browse surfaces (popular + search → add); My Library holds the user's RD content. One root
/// NavigationStack OUTSIDE the TabView so Detail / the player cover the tab bar cleanly.
struct LibraryShell: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        NavigationStack {
            TabView {
                Tab("Movies", systemImage: "film") { BrowseScreen(kind: .movie) }
                Tab("TV", systemImage: "tv") { BrowseScreen(kind: .show) }
                Tab("My Library", systemImage: "rectangle.stack") { MyLibraryScreen() }
                Tab("Settings", systemImage: "gearshape") { SettingsView() }
            }
            .navigationDestination(for: SearchHit.self) { hit in
                AddScreen(hit: hit)
            }
            .navigationDestination(for: MediaItem.self) { item in
                if let details = session.detailsProvider {
                    DetailView(item: item, details: details, watch: session.watchStore)
                }
            }
            .navigationDestination(for: PlaybackRequest.self) { request in
                let engine = VLCKitVideoPlayerEngine(preferences: session.subtitleSettings.preferences)
                if let model = session.makePlayer(for: request, engine: engine) {
                    PlayerView(model: model, engine: engine,
                               backdropURL: TMDBClient.imageURL(path: request.item.backdropPath, size: "original"))
                } else {
                    PlaybackUnavailableView()
                }
            }
        }
        // Load the library once on appear (re-runs when `retry()` bumps `attempt`). This also
        // populates ownership so Browse can badge titles already in the library.
        .task(id: session.libraryStore?.attempt ?? -1) {
            await session.libraryStore?.load()
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
