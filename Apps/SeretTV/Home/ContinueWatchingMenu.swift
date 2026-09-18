import DebridCore
import DebridUI
import SwiftUI

/// What a Continue Watching card offers on press-and-hold.
///
/// The rail had no menu at all, so whatever you started stayed on Home until you finished it —
/// a film opened for ten seconds sat at the top of the screen and took the hero with it, and the
/// only way to clear it was to play it to the end. Marking is the way out: both marks drop the
/// entry, because the rail is exactly the rows that are unfinished AND carry a position.
///
/// Both are offered rather than a toggle, for the reason `LibraryTitleActions` offers a show both:
/// a part-watched entry has no honest binary state, and the two mean different things — watched
/// keeps where you were and leaves a ✓, unwatched throws the resume point away.
struct ContinueWatchingActions: View {
    let entry: HomeItem
    /// The store to act on, passed rather than read off the session: the screen already holds it,
    /// and taking it explicitly is what lets the `-uiPreview home` harness drive a real mark.
    let home: HomeStore
    let session: AppSession

    /// A show's card stands for one episode, so its marks have to say so — "Mark Watched" on a
    /// series poster reads as the whole run.
    private var scope: String { entry.item.kind == .show ? "Episode " : "" }

    var body: some View {
        Button("Mark \(scope)Watched", systemImage: "checkmark.circle") { markEntry(true) }
        Button("Mark \(scope)Unwatched", systemImage: "circle") { markEntry(false) }
        if entry.item.kind == .show {
            Button("Mark Show Watched", systemImage: "checkmark.circle.fill") { markShow(true) }
            Button("Mark Show Unwatched", systemImage: "circle.dashed") { markShow(false) }
        }
    }

    /// The one movie or episode this card stands for.
    private func markEntry(_ watched: Bool) {
        let entry = entry, home = home, library = session.libraryStore
        Task {
            await home.setWatched(watched, entry: entry)
            await Self.refresh(home: home, library: library)
        }
    }

    /// Every episode of the series, the same fan-out the library grid offers. Detached from the
    /// gesture: a long-running show is hundreds of writes behind a TMDB enumeration, and the menu
    /// should dismiss immediately either way.
    private func markShow(_ watched: Bool) {
        // Writing against an unresolved profile produces a row keyed to "" that nothing adopts —
        // the marks would appear to do nothing and could not be undone from the UI.
        guard let profileID = session.activeProfileID else { return }
        let marker = session.makeShowWatchMarker()
        let show = entry.item
        let home = home, library = session.libraryStore
        Task {
            await marker?.mark(watched, show: show, profileID: profileID)
            await Self.refresh(home: home, library: library)
        }
    }

    /// Re-read watch state and recompose the rails, so the ✓ reaches Recently Added and the rail
    /// settles on what was actually written. Best-effort: `HomeStore` has already taken the card
    /// off the rail, and it has no library of its own to rebuild from, so with no library store
    /// there is simply nothing further to reconcile.
    private static func refresh(home: HomeStore, library: LibraryStore?) async {
        guard let library else { return }
        await library.reloadWatchStates()
        await home.rebuild(movies: library.movies, shows: library.shows)
    }
}
