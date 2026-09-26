import DebridCore
import DebridUI
import SwiftUI

/// What a pushed `.title` route renders: the harness's injected `DetailStore` when there is one,
/// otherwise one built from the session the same way a poster's Play button does (Decision 2) —
/// nil while signed out, in which case the hero placeholder is all there is to show.
///
/// Decision 3 — the page upgrades in place: once the library's item for this id (and kind — TMDB
/// movie/show ids share one integer space) differs from the store's own item, the store is
/// rebuilt over the library's item. That happens after an acquire, a download or a season pack
/// lands, or a version is removed, and it never touches an injected (harness) store.
struct TitleRoute: View {
    let item: MediaItem

    @Environment(DetailStore.self) private var injected: DetailStore?
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(LibraryStore.self) private var injectedLibrary: LibraryStore?
    @State private var store: DetailStore?

    private var library: LibraryStore? { injectedLibrary ?? session?.libraryStore }

    /// The library's own item for this title when it owns one under the same kind, else the route's
    /// original item.
    private var resolved: MediaItem {
        let owned = library?.movies.first { $0.id == item.id && $0.kind == item.kind }
            ?? library?.shows.first { $0.id == item.id && $0.kind == item.kind }
        return owned ?? item
    }

    var body: some View {
        Group {
            if let store {
                TitlePage(store: store)
            } else {
                TitleHeroPlaceholder(item: item)
            }
        }
        .task(id: resolved) {
            if let injected {
                if store == nil { store = injected }
                return
            }
            guard store == nil || store?.item != resolved else { return }
            // A show's selected season must survive the swap (e.g. a season pack landing on S2):
            // the new store defaults back to season 1 on its own, so hand it the old one's pick
            // before it ever renders.
            let previousSeason = store?.selectedSeason
            guard let newStore = session?.makeDetailStore(for: resolved) else { store = nil; return }
            if resolved.kind == .show, let previousSeason, previousSeason != newStore.selectedSeason {
                await newStore.selectSeason(previousSeason)
            }
            store = newStore
        }
    }
}
