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
        let entry = entry
        withRefresh { home, _ in await home.setWatched(watched, entry: entry) }
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
        withRefresh { _, _ in await marker?.mark(watched, show: show, profileID: profileID) }
    }

    /// Run a mark, then re-read watch state and recompose the rails, so the card leaves Continue
    /// Watching and its ✓ appears in Recently Added without waiting for Home to be revisited.
    private func withRefresh(_ mark: @escaping (HomeStore, LibraryStore) async -> Void) {
        guard let home = session.home, let library = session.libraryStore else { return }
        Task {
            await mark(home, library)
            await library.reloadWatchStates()
            await home.rebuild(movies: library.movies, shows: library.shows)
        }
    }
}
