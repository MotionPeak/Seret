import DebridCore
import DebridUI
import SwiftUI

/// A signed-in library tab. Reads the shared `LibraryStore` off `AppSession`, renders the
/// adaptive grid for its kind, kicks off `load()`, and opens a poster in full-screen Detail.
struct LibrarySection: View {
    @Environment(AppSession.self) private var session
    @State private var detailItem: MediaItem?
    let section: MainShell.Section

    var body: some View {
        Group {
            if let store = session.libraryStore {
                LibraryGrid(
                    title: section.title,
                    items: section == .shows ? store.shows : store.movies,
                    state: store.state,
                    onRetry: { store.retry() },
                    onSelect: { detailItem = $0 })
                .task(id: store.attempt) { await store.load() }
            } else {
                ProgressView().tint(Theme.Palette.gold)
            }
        }
        .fullScreenCover(item: $detailItem) { item in
            if let details = session.detailsProvider {
                DetailScreen(item: item, details: details, watch: session.watchStore)
            }
        }
    }
}
