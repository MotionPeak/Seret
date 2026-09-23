import DebridCore
import DebridUI
import SwiftUI

/// What a pushed `.title` route renders: the harness's injected `DetailStore` when there is one,
/// otherwise one built from the session the same way a poster's Play button does (Decision 2) —
/// nil while signed out, in which case the hero placeholder is all there is to show.
struct TitleRoute: View {
    let item: MediaItem

    @Environment(DetailStore.self) private var injected: DetailStore?
    @Environment(AppSession.self) private var session: AppSession?
    @State private var store: DetailStore?

    var body: some View {
        Group {
            if let store {
                TitlePage(store: store)
            } else {
                TitleHeroPlaceholder(item: item)
            }
        }
        .task(id: item.id) {
            if store == nil { store = injected ?? session?.makeDetailStore(for: item) }
        }
    }
}
