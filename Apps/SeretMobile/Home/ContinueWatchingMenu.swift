import DebridCore
import DebridUI
import SwiftUI

/// What a Continue Watching card offers on long-press — the same actions the Apple TV offers.
///
/// The phone's rail had no menu at all: a title opened for ten seconds stayed on Home until it was
/// played to the end, and nothing on Home led to its page (a tap RESUMES). Marking is the way off
/// the rail, because the rail is exactly the rows that are unfinished AND carry a position.
///
/// Both marks are offered rather than a toggle: a part-watched entry has no honest binary state,
/// and they mean different things — watched keeps where you were and leaves a ✓, unwatched throws
/// the resume point away.
struct ContinueWatchingActions: View {
    let entry: HomeItem
    let home: HomeStore
    let session: AppSession
    /// Opens the title's page.
    var openTitle: () -> Void = {}

    /// A show's card stands for one episode, so its marks have to say so.
    private var scope: String { entry.item.kind == .show ? "Episode " : "" }

    var body: some View {
        Button(entry.item.kind == .show ? "Go to Show" : "Go to Movie", systemImage: "info.circle") {
            openTitle()
        }
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

    /// Every episode of the series. Detached from the gesture: a long-running show is hundreds of
    /// writes behind a TMDB enumeration, and the menu should dismiss immediately either way.
    private func markShow(_ watched: Bool) {
        // A write against an unresolved profile is keyed to "" and adopted by nothing.
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
    /// settles on what was actually written.
    private static func refresh(home: HomeStore, library: LibraryStore?) async {
        guard let library else { return }
        await library.reloadWatchStates()
        await home.rebuild(movies: library.movies, shows: library.shows)
    }
}
