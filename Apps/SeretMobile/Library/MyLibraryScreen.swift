import DebridCore
import DebridUI
import SwiftUI

/// The user's Real-Debrid library, split into Movies / TV via a segmented control. Reuses the
/// existing adaptive `LibraryGrid` and Detail/play path off the shared `LibraryStore`.
struct MyLibraryScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var kind: MediaKind = .movie
    @State private var pendingRemoval: MediaItem?
    @State private var removeErrorMessage: String?

    /// My Library shows the whole Real-Debrid library (every title you've added) — the Movies/TV
    /// picker is the only filter.
    private func items(_ store: LibraryStore) -> [MediaItem] {
        kind == .movie ? store.movies : store.shows
    }

    /// Finished-movie ids for the ✓ badge (movies only; a movie's content key IS its id).
    private func watchedMovieIDs(_ store: LibraryStore) -> Set<String> {
        Set(store.watchByKey.filter { $0.value.finished }.map(\.key))
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(spacing: Theme.Space.sm) {
                Picker("Library section", selection: $kind) {
                    Text("Movies").tag(MediaKind.movie)
                    Text("TV").tag(MediaKind.show)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Space.lg)
                .padding(.top, Theme.Space.sm)

                if let tiles = session.downloadStore?.activeTiles, !tiles.isEmpty {
                    DownloadingStrip(tiles: tiles)
                }

                if let store = session.libraryStore {
                    LibraryGrid(
                        title: kind == .movie ? "Movies" : "Shows",
                        items: items(store),
                        state: store.state,
                        onRetry: { store.retry() },
                        onSelect: { router.detail = $0 },
                        onRemove: { pendingRemoval = $0 },
                        watchedMovieIDs: watchedMovieIDs(store),
                        onToggleWatched: { item in
                            let isWatched = store.watchByKey[item.id]?.finished == true
                            Task { await store.setWatched(!isWatched, for: item) }
                        })
                        .task(id: store.attempt) { await store.load() }
                        // Watch state is per-profile — reload the ✓ badges when the active profile
                        // changes (an id-less .task would keep the previous profile's badges).
                        .task(id: session.activeProfileID) { await store.reloadWatchStates() }
                        .confirmationDialog(
                            "Remove \u{201C}\(pendingRemoval?.title ?? "")\u{201D} from your library?",
                            isPresented: Binding(get: { pendingRemoval != nil },
                                                 set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingRemoval) { item in
                            Button("Remove", role: .destructive) {
                                Task { await store.remove(item) }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: { _ in
                            Text("This deletes it from your Real\u{2011}Debrid account.")
                        }
                        .onChange(of: store.removal) { _, newValue in
                            if case .failed(let msg) = newValue { removeErrorMessage = msg }
                        }
                        .alert("Couldn\u{2019}t Remove", isPresented: Binding(
                            get: { removeErrorMessage != nil },
                            set: { if !$0 { removeErrorMessage = nil; store.clearRemovalError() } })) {
                            Button("OK", role: .cancel) { removeErrorMessage = nil; store.clearRemovalError() }
                        } message: {
                            Text(removeErrorMessage ?? "")
                        }
                } else {
                    Spacer(); ProgressView().tint(Theme.Palette.gold); Spacer()
                }
            }
        }
        .navigationTitle("My Library")
    }
}

/// A horizontal strip of in-progress downloads shown above the library grid, so a requested title
/// is visible (with live progress) before it finishes and becomes a normal library item.
private struct DownloadingStrip: View {
    let tiles: [DownloadTile]
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("DOWNLOADING").font(Theme.Typo.label()).tracking(1.5)
                .foregroundStyle(Theme.Palette.gold).padding(.horizontal, Theme.Space.lg)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.md) {
                    ForEach(tiles) { DownloadingTile(tile: $0) }
                }
                .padding(.horizontal, Theme.Space.lg)
            }
        }
        .padding(.top, Theme.Space.sm)
    }
}
