import DebridCore

/// The search field's scope: **All** (movies + shows merged best-first) or one kind. Pure so the
/// mapping to `SearchStore.search(query:kind:)`'s `kind` parameter is unit-tested on its own.
enum SearchScope: String, CaseIterable, Identifiable {
    case all, movies, shows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .movies: "Movies"
        case .shows: "Shows"
        }
    }

    var kind: MediaKind? {
        switch self {
        case .all: nil
        case .movies: .movie
        case .shows: .show
        }
    }
}

/// What debounces: a query trimmed of surrounding space, paired with the scope it was typed under
/// — so switching Movies/Shows re-searches even if the text itself didn't change, and " dune " and
/// "dune" collapse to the same request.
struct SearchRequestKey: Hashable {
    let query: String
    let scope: SearchScope

    init(query: String, scope: SearchScope) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scope = scope
    }

    var isEmpty: Bool { query.isEmpty }
}
