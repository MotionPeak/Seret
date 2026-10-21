import DebridCore
import DebridUI
import SwiftUI

/// Focus bookkeeping Home writes on every focus move. A plain reference held in `@State`, so
/// writing it never re-renders Home — nothing in it is drawn.
@MainActor
final class HomeFocusMemory {
    /// The tile focus is on, or was last on.
    var lastFocused: String?
    /// A tile has taken focus since Home appeared — from then on focus, not the data, says what the
    /// header shows.
    var tileHasFocused = false
    /// The tile a long-press action was just taken on. Its menu holds focus while it is open, so
    /// when the action takes the tile away there is no focused tile to notice it went.
    var actedOn: String?
    /// A focus hand-on in progress (see `HomeScreen.rehomeFocus`).
    var rehomeTask: Task<Void, Never>?
    /// Recording that focus left Home's tiles, once it has settled (see `tileFocusChanged`).
    var departure: Task<Void, Never>?
}

extension HomeScreen {
    /// Every tile's focus id, rail by rail, in screen order: Continue Watching, Downloading, then
    /// the watchlist rows — or, with no Letterboxd account (`picks` nil), Recently Added.
    func tileKeys(_ home: HomeStore, picks: HomeWatchlistRows?) -> [String] {
        let leading = home.continueWatching.map { Self.focusID(Rail.continueWatching, $0.id) }
            + activeDownloads.map { Self.focusID(Rail.downloading, $0.id) }
        guard let picks else {
            return leading
                + home.recentlyAddedMovies.map { Self.focusID(Rail.movies, $0.id) }
                + home.recentlyAddedShows.map { Self.focusID(Rail.shows, $0.id) }
        }
        return leading
            + picks.picked.map { Self.focusID(Rail.picked, $0.id) }
            + picks.both.map { Self.focusID(Rail.both, $0.id) }
    }

    func tileFocusChanged(_ key: String?) {
        focusMemory.departure?.cancel()
        if let key {
            focusMemory.actedOn = nil
            focusMemory.lastFocused = key
            return
        }
        // Focus left Home's tiles (the menu, a long-press menu, a pushed page): coming back in
        // lands where it left from. Settled first — a move from one rail to the next passes through
        // "nothing focused" for an instant, and recording that would re-render Home per rail change.
        let handle = focusHandle, memory = focusMemory, entry = $entryTile
        memory.departure = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, handle.focused == nil,
                  entry.wrappedValue != memory.lastFocused else { return }
            entry.wrappedValue = memory.lastFocused
        }
    }

    /// Hands focus on when the tile that had it — or whose long-press menu had it — is gone.
    ///
    /// tvOS leaves NOTHING focused in that case (measured: no ring anywhere, the header still
    /// describing the gone title) until the next press. Only then, though: a tile leaving while
    /// focus is anywhere else — the side menu, another tile, another page — must not pull focus.
    func rehomeFocus(old: [String], new: [String]) {
        guard !sideMenuFocus.holdsFocus, isVisiblePage else { return }
        let gone: String
        if let focused = focusHandle.focused, !new.contains(focused) {
            gone = focused
        } else if focusHandle.focused == nil, let acted = focusMemory.actedOn, !new.contains(acted) {
            gone = acted
        } else {
            return
        }
        focusMemory.actedOn = nil
        guard let next = RailFocusNeighbour.of(gone, old: old, new: new) else { return }
        // Retried, not set once: while a long-press menu is still animating away tvOS ignores the
        // write (measured: ~0.9s of no-ops in the simulator, then it lands). The tile it names may
        // also be one this same change inserts — a show's card moving on to its next episode.
        // The first write that lands ends it, and so does focus reaching any other tile; the side
        // menu taking focus ends it (checked before every write) and Home leaving the screen
        // cancels it (`cancelRehome`).
        cancelRehome()
        let handle = focusHandle, menu = sideMenuFocus
        focusMemory.rehomeTask = Task { @MainActor in
            for _ in 0..<20 {
                if menu.holdsFocus { return }
                handle.move(to: next)
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
                if let now = handle.focused, now != gone { return }
            }
        }
    }

    func cancelRehome() {
        focusMemory.rehomeTask?.cancel()
        focusMemory.rehomeTask = nil
    }
}
