import DebridCore
import DebridUI
import SwiftUI

/// The user's Real-Debrid library, split into Movies / TV via a segmented control. Reuses the
/// existing adaptive `LibraryGrid` and Detail/play path off the shared `LibraryStore`.
struct MyLibraryScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var kind: MediaKind = .movie
    @State private var pendingRemoval: MediaItem?

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
                        onSelect: { router.detail = $0 },
                        onRemove: { pendingRemoval = $0 })
                        .task(id: store.attempt) { await store.load() }
                        .confirmationDialog(
                            "Remove \u{201C}\(pendingRemoval?.title ?? "")\u{201D} from your library?",
                            isPresented: Binding(get: { pendingRemoval != nil },
                                                 set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingRemoval) { item in
                            Button("Remove", role: .destructive) {
                                Task { await store.remove(item) }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: { _ in
                            Text("This deletes it from your Real\u{2011}Debrid account.")
                        }
                        .alert("Couldn\u{2019}t Remove", isPresented: Binding(
                            get: { if case .failed = store.removal { return true } else { return false } },
                            set: { if !$0 { store.clearRemovalError() } })) {
                            Button("OK", role: .cancel) { store.clearRemovalError() }
                        } message: {
                            if case .failed(let msg) = store.removal { Text(msg) }
                        }
                } else {
                    Spacer(); ProgressView().tint(Theme.Palette.gold); Spacer()
                }
            }
        }
        .navigationTitle("My Library")
    }
}
