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
    /// The index of the row focus is in, or was last in — where focus goes when that row leaves.
    var lastRowIndex: Int?
    /// Recording that focus left the page, once it has settled (see `focusChanged`).
    var departure: Task<Void, Never>?
    /// The tile a long-press action was just taken on (Watchlist's Remove). Its menu and the
    /// confirmation hold focus meanwhile, so when the action takes the tile away there is no
    /// focused tile to notice it went.
    var actedOn: String?
    /// A focus hand-on in progress (see `WatchlistScreen.rehomeFocus`).
    var rehomeTask: Task<Void, Never>?
}

extension BrowseScreen {
    static func tileID(_ row: String, _ hit: SearchHit) -> String { "\(row)/\(hit.id)" }
    static func seeAllID(_ genre: DiscoverStore.Genre) -> String { "seeall/\(genre.tmdbID)" }

    /// The first tile of the row at `index` (clamped to the last row), if there is one.
    static func firstTileID(ofRowAt index: Int?, in rows: [DiscoverStore.Row]) -> String? {
        guard let index, !rows.isEmpty else { return nil }
        let row = rows[min(max(index, 0), rows.count - 1)]
        return row.hits.first.map { tileID(row.id, $0) }
    }

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
