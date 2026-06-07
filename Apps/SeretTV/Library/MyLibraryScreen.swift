import DebridCore
import DebridUI
import SwiftUI

/// The user's Real-Debrid library, split into Movies / TV via a focusable selector over the
/// shared `LibraryStore`. Reuses `LibraryScreen` (states + poster grid + Detail/play).
struct MyLibraryScreen: View {
    @Environment(AppSession.self) private var session
    @State private var kind: MediaKind = .movie
    @State private var pendingRemoval: MediaItem?

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 24) {
                Button("Movies") { kind = .movie }
                    .font(.headline).tint(kind == .movie ? .white : .secondary)
                Button("TV Shows") { kind = .show }
                    .font(.headline).tint(kind == .show ? .white : .secondary)
            }
            .padding(.top, 30)

            if let store = session.libraryStore {
                LibraryScreen(
                    title: kind == .movie ? "Movies" : "Shows",
                    items: kind == .movie ? store.movies : store.shows,
                    state: store.state,
                    onRetry: { store.retry() },
                    onRemove: { pendingRemoval = $0 })
                    .alert("Remove \u{201C}\(pendingRemoval?.title ?? "")\u{201D}?",
                           isPresented: Binding(get: { pendingRemoval != nil },
                                                set: { if !$0 { pendingRemoval = nil } })) {
                        Button("Remove", role: .destructive) {
                            if let item = pendingRemoval { Task { await store.remove(item) } }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
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
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
