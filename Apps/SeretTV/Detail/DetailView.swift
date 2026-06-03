import DebridCore
import SwiftUI

/// Owns the per-title `DetailStore` and routes to the movie or show layout.
struct DetailView: View {
    @State private var store: DetailStore

    init(item: MediaItem, details: MediaDetailsProviding, watch: WatchProgressProviding?) {
        _store = State(initialValue: DetailStore(item: item, details: details, watch: watch))
    }

    var body: some View {
        Group {
            switch store.item.kind {
            case .movie: MovieDetailView(store: store)
            case .show:  Text("Show detail — Task 7").font(.title)   // replaced in Task 7
            }
        }
        .task { await store.load() }
    }
}
