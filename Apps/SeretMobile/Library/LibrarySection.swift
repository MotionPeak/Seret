import DebridCore
import DebridUI
import SwiftUI

/// A signed-in library tab. Reads the shared `LibraryStore` off `AppSession`, renders the
/// adaptive grid for its kind, kicks off `load()`, and opens a poster in full-screen Detail.
struct LibrarySection: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    let section: MainShell.Section

    var body: some View {
        Group {
            if let store = session.libraryStore {
                LibraryGrid(
                    title: section.title,
                    items: section == .shows ? store.shows : store.movies,
                    state: store.state,
                    onRetry: { store.retry() },
                    onSelect: { router.detail = $0 })
                .task(id: store.attempt) { await store.load() }
            } else {
                ProgressView().tint(Theme.Palette.gold)
            }
        }
    }
}
