import DebridCore
import DebridUI
import SwiftUI

/// Focus bookkeeping the browse page writes on every focus move. A plain reference held in
/// `@State`, so writing it never re-renders the page — nothing in it is drawn.
@MainActor
final class BrowseFocusMemory {
    /// The view focus is on, or was last on.
    var lastFocused: String?
    /// The segment whose tile last drove the header. While it is not the segment on screen, the
    /// header follows the data (the segment's first title) instead of focus.
    var headerSegment: DiscoverStore.Segment?
    /// Recording that focus left the page, once it has settled (see `focusChanged`).
    var departure: Task<Void, Never>?
}

extension BrowseScreen {
    static func tileID(_ row: String, _ hit: SearchHit) -> String { "\(row)/\(hit.id)" }
    static func segmentID(_ segment: DiscoverStore.Segment) -> String { "segment/\(segment.rawValue)" }

    /// Every focus id on the page: the controls, then each rail's tiles.
    func focusKeys(_ rows: [DiscoverStore.Row]) -> Set<String> {
        var keys = Set(DiscoverStore.Segment.allCases.map(Self.segmentID))
        keys.insert(GenreStrip.focusID(for: nil))
        for genre in DiscoverStore.genres(for: kind) { keys.insert(GenreStrip.focusID(for: genre)) }
        for row in rows { for hit in row.hits { keys.insert(Self.tileID(row.id, hit)) } }
        return keys
    }

    /// What the header shows while it follows the data: the segment and its first title.
    func headerKey(_ segment: DiscoverStore.Segment, _ rows: [DiscoverStore.Row]) -> String {
        "\(segment.rawValue)|\(rows.first?.hits.first?.id ?? "")"
    }

    func focusChanged(_ key: String?) {
        focusMemory.departure?.cancel()
        if let key {
            focusMemory.lastFocused = key
            return
        }
        // Focus left the page (the side menu, a pushed title, the genre grid, a long-press menu):
        // coming back in lands where it left from. Settled first — a move from one row to the next
        // passes through "nothing focused" for an instant, and recording that would re-render the
        // page per rail change.
        let handle = focusHandle, memory = focusMemory, entry = $entryFocus
        memory.departure = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, handle.focused == nil,
                  entry.wrappedValue != memory.lastFocused else { return }
            entry.wrappedValue = memory.lastFocused
        }
    }
}
