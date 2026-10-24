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

    /// - Parameter accounts: the signed-in debrid accounts, which the empty state names.
    static func make(state: LibraryStore.State, items: [MediaItem], kind: MediaKind,
                     accounts: [DebridProvider]) -> LibraryPageContent {
        switch state {
        case .loading:
            return .skeleton
        case .failed(let message):
            return .failed(message)
        case .empty:
            return .empty(title: "Nothing in your library yet",
                         detail: "Add something to \(DebridCopy.accounts(accounts)) and it appears here.")
        case .loaded:
            guard !items.isEmpty else {
                return .empty(title: kind == .movie ? "No movies yet" : "No shows yet", detail: nil)
            }
            return .grid
        }
    }
}
