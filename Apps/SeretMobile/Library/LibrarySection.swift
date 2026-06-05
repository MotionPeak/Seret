import DebridCore
import DebridUI
import SwiftUI

/// A signed-in library tab. Reads the shared `LibraryStore` off `AppSession`, renders the
/// adaptive grid for its kind, kicks off `load()` (re-running on `retry()`), and routes a
/// poster tap to Detail. Movies vs. Shows is decided by `section`.
struct LibrarySection: View {
    @Environment(AppSession.self) private var session
    let section: MainShell.Section

    var body: some View {
        Group {
            if let store = session.libraryStore {
                LibraryGrid(
                    title: section.title,
                    items: section == .shows ? store.shows : store.movies,
                    state: store.state,
                    onRetry: { store.retry() })
                .navigationDestination(for: MediaItem.self) { item in
                    DetailPlaceholder(item: item)
                }
                .task(id: store.attempt) { await store.load() }
            } else {
                ProgressView()
            }
        }
    }
}

/// Temporary Detail target until 8b's next increment wires the real movie/show Detail.
struct DetailPlaceholder: View {
    let item: MediaItem

    var body: some View {
        ContentUnavailableView {
            Label(item.title, systemImage: "play.rectangle")
        } description: {
            Text("Detail + playback land in the next step.")
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
