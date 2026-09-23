import DebridCore
import DebridUI

/// What the My Library screen shows for one tab (Movies or Shows), derived from the store's state
/// and the already-filtered item list. Pure so the state → screen mapping is unit-tested without a
/// view or a store.
enum LibraryPageContent: Equatable {
    case skeleton
    case grid
    case empty(title: String, detail: String?)
    case failed(String)

    static func make(state: LibraryStore.State, items: [MediaItem], kind: MediaKind) -> LibraryPageContent {
        switch state {
        case .loading:
            return .skeleton
        case .failed(let message):
            return .failed(message)
        case .empty:
            return .empty(title: "Nothing in your library yet",
                         detail: "Add something to your Real\u{2011}Debrid account and it appears here.")
        case .loaded:
            guard !items.isEmpty else {
                return .empty(title: kind == .movie ? "No movies yet" : "No shows yet", detail: nil)
            }
            return .grid
        }
    }
}
