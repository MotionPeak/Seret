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
                    if let details = session.detailsProvider {
                        DetailScreen(item: item, details: details, watch: session.watchStore)
                    }
                }
                .task(id: store.attempt) { await store.load() }
            } else {
                ProgressView()
            }
        }
    }
}
