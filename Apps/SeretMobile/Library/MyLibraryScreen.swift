import DebridCore
import DebridUI
import SwiftUI

/// The user's Real-Debrid library, split into Movies / TV via a segmented control. Reuses the
/// existing adaptive `LibraryGrid` and Detail/play path off the shared `LibraryStore`.
struct MyLibraryScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var kind: MediaKind = .movie

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(spacing: Theme.Space.sm) {
                Picker("Library section", selection: $kind) {
                    Text("Movies").tag(MediaKind.movie)
                    Text("TV").tag(MediaKind.show)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Space.lg)
                .padding(.top, Theme.Space.sm)

                if let store = session.libraryStore {
                    LibraryGrid(
                        title: kind == .movie ? "Movies" : "Shows",
                        items: kind == .movie ? store.movies : store.shows,
                        state: store.state,
                        onRetry: { store.retry() },
                        onSelect: { router.detail = $0 })
                        .task(id: store.attempt) { await store.load() }
                } else {
                    Spacer(); ProgressView().tint(Theme.Palette.gold); Spacer()
                }
            }
        }
        .navigationTitle("My Library")
    }
}
