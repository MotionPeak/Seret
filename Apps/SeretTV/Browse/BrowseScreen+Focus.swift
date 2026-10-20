import DebridCore
import DebridUI
import SwiftUI

/// Focus bookkeeping the browse page writes on every focus move. A plain reference held in
/// `@State`, so writing it never re-renders the page — nothing in it is drawn.
@MainActor
final class BrowseFocusMemory {
    /// The view focus is on, or was last on.
    var lastFocused: String?
    /// A tile has had focus. Until then the header follows the data (the page's first title)
    /// instead of focus.
    var tileHasHadFocus = false
    /// Recording that focus left the page, once it has settled (see `focusChanged`).
    var departure: Task<Void, Never>?
}

extension BrowseScreen {
    static func tileID(_ row: String, _ hit: SearchHit) -> String { "\(row)/\(hit.id)" }
    static func seeAllID(_ genre: DiscoverStore.Genre) -> String { "seeall/\(genre.tmdbID)" }

    /// Every focus id on the page: the failed row's Retry while it is up, each rail's tiles, and
    /// each genre row's See All.
    func focusKeys(_ rows: [DiscoverStore.Row], retry: Bool) -> Set<String> {
        var keys = Set<String>()
        if retry { keys.insert(PageRow.retry) }
        for row in rows {
            for hit in row.hits { keys.insert(Self.tileID(row.id, hit)) }
            if let genre = row.genre { keys.insert(Self.seeAllID(genre)) }
        }
        return keys
    }

    func focusChanged(_ key: String?) {
        focusMemory.departure?.cancel()
        if let key {
            focusMemory.lastFocused = key
            return
        }
        // Focus left the page (the side menu, a pushed title or genre, a long-press menu): coming
        // back in lands where it left from. Settled first — a move from one row to the next passes
        // through "nothing focused" for an instant, and recording that would re-render the page
        // per rail change.
        let handle = focusHandle, memory = focusMemory, entry = $entryFocus
        memory.departure = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, handle.focused == nil,
                  entry.wrappedValue != memory.lastFocused else { return }
            entry.wrappedValue = memory.lastFocused
        }
    }
}
