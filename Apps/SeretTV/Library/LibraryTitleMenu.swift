import DebridCore
import DebridUI
import SwiftUI

/// The actions a library title offers, defined once and attached wherever a title appears.
///
/// They used to be written out per screen, and each copy had drifted: the library grid could mark a
/// movie watched but not a show, the Home rail could mark a movie watched but never remove
/// anything, and Find could mark either but also never remove. Which actions you got depended on
/// which grid you happened to be looking at — the reported "it doesn't let me mark watched or
/// remove in all screens".
///
/// A show is offered both marks rather than a toggle. A part-watched series has no honest binary
/// state, and saying "Mark Show Watched" when eleven of thirteen episodes are done is a guess.
extension View {
    /// - Parameter onRemove: nil for a title that is not in the library (a Find result you don't
    ///   own), which is the one case where removal is not an available action.
    func libraryTitleMenu(for item: MediaItem,
                          session: AppSession,
                          onRemove: ((MediaItem) -> Void)?) -> some View {
        contextMenu {
            LibraryTitleActions(item: item, session: session, onRemove: onRemove)
        }
    }
}

struct LibraryTitleActions: View {
    let item: MediaItem
    let session: AppSession
    let onRemove: ((MediaItem) -> Void)?

    private var isWatched: Bool {
        session.libraryStore?.watchState(for: item)?.finished == true
    }

    var body: some View {
        switch item.kind {
        case .movie:
            Button(isWatched ? "Mark Unwatched" : "Mark Watched",
                   systemImage: isWatched ? "checkmark.circle.fill" : "checkmark.circle") {
                guard let store = session.libraryStore else { return }
                Task { await store.setWatched(!isWatched, for: item) }
            }
        case .show:
            Button("Mark Show Watched", systemImage: "checkmark.circle") { markShow(true) }
            Button("Mark Show Unwatched", systemImage: "circle") { markShow(false) }
        }
        if let onRemove {
            Button("Remove from Library", systemImage: "trash", role: .destructive) {
                onRemove(item)
            }
        }
    }

    /// Detached from the gesture: a long-running series is hundreds of episode writes behind a
    /// TMDB enumeration, and the menu should dismiss immediately either way.
    private func markShow(_ watched: Bool) {
        let profileID = session.activeProfileID ?? ""
        let marker = session.makeShowWatchMarker()
        let store = session.libraryStore
        Task {
            await marker?.mark(watched, show: item, profileID: profileID)
            await store?.reloadWatchStates()
        }
    }
}

/// The confirm-then-remove flow, so any screen offering removal gets the same two alerts.
///
/// The library grid grew this inline; Home had no removal at all. Extracting it is what made
/// adding removal to a second screen a one-line change rather than a copied thirty.
extension View {
    func libraryRemovalConfirmation(pending: Binding<MediaItem?>,
                                    errorMessage: Binding<String?>,
                                    store: LibraryStore?) -> some View {
        modifier(LibraryRemovalConfirmation(pending: pending, errorMessage: errorMessage,
                                            store: store))
    }
}

struct LibraryRemovalConfirmation: ViewModifier {
    @Binding var pending: MediaItem?
    @Binding var errorMessage: String?
    let store: LibraryStore?

    func body(content: Content) -> some View {
        content
            .alert("Remove \u{201C}\(pending?.title ?? "")\u{201D}?",
                   isPresented: Binding(get: { pending != nil },
                                        set: { if !$0 { pending = nil } })) {
                Button("Remove", role: .destructive) {
                    guard let item = pending, let store else { return }
                    Task {
                        await store.remove(item)
                        if case .failed(let msg) = store.removal {
                            errorMessage = msg
                            store.clearRemovalError()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes it from your Real\u{2011}Debrid account.")
            }
            .alert("Couldn\u{2019}t Remove", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }
}

/// How a poster anywhere in the app asks for a title to be removed.
///
/// `BrowseTile` renders in five places — the browse rails, a genre grid, a person's credits, the
/// "More Like This" rail and Search — so threading a callback to each would be five signatures and
/// five copies of the confirmation. The shell sets this once and hosts the alerts; a tile just
/// calls it.
///
/// The default is a no-op rather than a required value on purpose: a plain closure cannot trap the
/// way a missing `@Observable` environment object does, so a tile rendered outside the shell (a
/// preview, the `-uiPreview` harness) silently offers nothing instead of killing the process.
private struct LibraryRemovalRequestKey: EnvironmentKey {
    static let defaultValue: @MainActor (MediaItem) -> Void = { _ in }
}

extension EnvironmentValues {
    var requestLibraryRemoval: @MainActor (MediaItem) -> Void {
        get { self[LibraryRemovalRequestKey.self] }
        set { self[LibraryRemovalRequestKey.self] = newValue }
    }
}
