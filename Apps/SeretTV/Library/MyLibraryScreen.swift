import DebridCore
import DebridUI
import SwiftUI

/// The user's Real-Debrid library, split into Movies / TV via a focusable selector over the
/// shared `LibraryStore`. Reuses `LibraryScreen` (states + poster grid + Detail/play).
struct MyLibraryScreen: View {
    @Environment(AppSession.self) private var session
    @State private var kind: MediaKind = .movie

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
                    onRetry: { store.retry() })
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
