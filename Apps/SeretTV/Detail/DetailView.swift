import DebridCore
import DebridUI
import SwiftUI

struct DetailView: View {
    @State private var store: DetailStore
    @State private var confirmingRemove = false
    @State private var removeError: String?
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    init(item: MediaItem, details: MediaDetailsProviding, watch: WatchProgressProviding?) {
        _store = State(initialValue: DetailStore(item: item, details: details, watch: watch))
    }

    var body: some View {
        Group {
            switch store.item.kind {
            case .movie: MovieDetailView(store: store, onRemove: { confirmingRemove = true })
            case .show:  ShowDetailView(
                store: store, onRemove: { confirmingRemove = true },
                makeSeasonDownload: { imdb, season, lang in
                    session.makeSeasonDownload(imdbID: imdb, season: season, originalLanguage: lang)
                },
                onSeasonAdded: { session.libraryStore?.retry() })
            }
        }
        .task { await store.load() }
        .alert("Remove \u{201C}\(store.item.title)\u{201D}?", isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive) { performRemove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes it from your Real\u{2011}Debrid account. You can re\u{2011}add it later by searching.")
        }
        .alert("Couldn\u{2019}t Remove", isPresented: Binding(
            get: { removeError != nil }, set: { if !$0 { removeError = nil } })) {
            Button("OK", role: .cancel) { removeError = nil }
        } message: {
            Text(removeError ?? "")
        }
    }

    private func performRemove() {
        guard let library = session.libraryStore else { return }
        Task {
            await library.remove(store.item)
            if case .failed(let message) = library.removal {
                removeError = message
                library.clearRemovalError()
            } else {
                dismiss()
            }
        }
    }
}
