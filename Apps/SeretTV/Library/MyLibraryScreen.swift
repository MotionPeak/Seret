import DebridCore
import DebridUI
import SwiftUI

/// The user's Real-Debrid library, split into Movies / TV via a focusable selector over the
/// shared `LibraryStore`. Reuses `LibraryScreen` (states + poster grid + Detail/play).
struct MyLibraryScreen: View {
    @Environment(AppSession.self) private var session
    @State private var kind: MediaKind = .movie
    @State private var pendingRemoval: MediaItem?
    @State private var removeErrorMessage: String?
    /// Which kind pill has focus. Focus only highlights; a Select press switches the kind
    /// (commit-on-press).
    @FocusState private var focusedKind: MediaKind?

    /// My Library shows the whole Real-Debrid library (every title you've added) — the Movies/TV
    /// selector is the only filter.
    private func items(_ store: LibraryStore) -> [MediaItem] {
        kind == .movie ? store.movies : store.shows
    }

    /// Finished ids for the ✓ badge — a title's content key IS its id, for movies and shows alike.
    private func watchedIDs(_ store: LibraryStore) -> Set<String> {
        Set(store.watchByKey.filter { $0.value.finished }.map(\.key))
    }

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 24) {
                Button("Movies") { kind = .movie }
                    .buttonStyle(SeretPillStyle(selected: kind == .movie))
                    .focused($focusedKind, equals: .movie)
                Button("TV Shows") { kind = .show }
                    .buttonStyle(SeretPillStyle(selected: kind == .show))
                    .focused($focusedKind, equals: .show)
            }
            .padding(.top, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The grid below already has a section (so DOWN worked); the pills did not (so UP did not).
            .focusSection()

            if let tiles = session.downloadStore?.activeTiles, !tiles.isEmpty {
                DownloadingStrip(tiles: tiles)
            }

            if let store = session.libraryStore {
                LibraryScreen(
                    title: kind == .movie ? "Movies" : "Shows",
                    items: items(store),
                    state: store.state,
                    onRetry: { store.retry() },
                    watchedIDs: watchedIDs(store),
                    session: session,
                    onRemove: { pendingRemoval = $0 })
                    .task(id: session.activeProfileID) { await store.reloadWatchStates() }
                    .libraryRemovalConfirmation(pending: $pendingRemoval,
                                                errorMessage: $removeErrorMessage,
                                                store: store)
                    .focusSection()      // let DOWN from the Movies/TV pills enter the grid and scroll it
                                          // (same fix as SettingsView / the player SettingsPanel)
            } else {
                SeretLoader()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A horizontal strip of in-progress downloads above the library grid, so a requested title is
/// visible (with live progress) before it finishes and becomes a normal library item.
private struct DownloadingStrip: View {
    let tiles: [DownloadTile]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Downloading").font(.seret(.title3, .bold))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.Layout.contentMargin)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    ForEach(tiles) { DownloadingTile(tile: $0) }
                }
                .padding(.horizontal, Theme.Layout.contentMargin)
            }
        }
    }
}
