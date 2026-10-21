import DebridCore
import DebridUI
import SwiftUI

/// The user's Real-Debrid library, split into Movies / TV via a focusable selector over the
/// shared `LibraryStore`. Reuses `LibraryScreen` (states + poster grid + Detail/play), over the
/// focused title's ultrablur (`GridBackdrop`).
struct MyLibraryScreen: View {
    @Environment(AppSession.self) private var session
    @State private var kind: MediaKind = .movie
    @State private var pendingRemoval: MediaItem?
    @State private var removeErrorMessage: String?
    /// Which kind pill has focus. Focus only highlights; a Select press switches the kind
    /// (commit-on-press).
    @FocusState private var focusedKind: MediaKind?
    /// The backdrop's subject: cards report focus, it publishes the one focus settles on. Only the
    /// backdrop reads it, so a move across the grid never re-renders this screen.
    @State private var preview = FocusPreviewModel()

#if DEBUG
    /// The `-uiPreview library` harness's stores (the unsigned preview session has none).
    var previewLibrary: LibraryStore?
    var previewArt: TitleArtStore?
    var previewDownloads: [DownloadTile]?
    /// What a download that left the list became (the preview session has no download store).
    var previewSettledPhase: DownloadStatus.Phase?
    private var library: LibraryStore? { previewLibrary ?? session.libraryStore }
    private var art: TitleArtStore? { previewArt ?? session.titleArt }
    private var downloads: [DownloadTile] { previewDownloads ?? session.downloadStore?.activeTiles ?? [] }
    private func downloadPhase(_ tile: DownloadTile) -> DownloadStatus.Phase? {
        previewSettledPhase ?? session.downloadStore?.statuses[tile.status.storeKey]?.phase
    }
#else
    private var library: LibraryStore? { session.libraryStore }
    private var art: TitleArtStore? { session.titleArt }
    private var downloads: [DownloadTile] { session.downloadStore?.activeTiles ?? [] }
    private func downloadPhase(_ tile: DownloadTile) -> DownloadStatus.Phase? {
        session.downloadStore?.statuses[tile.status.storeKey]?.phase
    }
#endif

    /// My Library shows the whole Real-Debrid library (every title you've added) — the Movies/TV
    /// selector is the only filter.
    private func items(_ store: LibraryStore) -> [MediaItem] {
        kind == .movie ? store.movies : store.shows
    }

    /// Finished ids for the ✓ badge — a title's content key IS its id, for movies and shows alike.
    private func watchedIDs(_ store: LibraryStore) -> Set<String> {
        Set(store.watchByKey.filter { $0.value.finished }.map(\.key))
    }

    @Environment(\.shellPageVisible) private var visible

    var body: some View {
        if visible {
            page
        } else {
            // Kept alive behind another page: state only, no tiles (see `ShellPageVisibleKey`).
            Color.clear
        }
    }

    private var page: some View {
        // No gap of its own under the pills: the scroll below starts with its top fade band.
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                Button("Movies") { kind = .movie }
                    .buttonStyle(SeretPillStyle(selected: kind == .movie))
                    .focused($focusedKind, equals: .movie)
                Button("TV Shows") { kind = .show }
                    .buttonStyle(SeretPillStyle(selected: kind == .show))
                    .focused($focusedKind, equals: .show)
            }
            .padding(.top, 30)
            // The grid's own inset, so the pills line up with its first column.
            .padding(.horizontal, PosterGridLayout.rootInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The grid below already has a section (so DOWN worked); the pills did not (so UP did not).
            .focusSection()

            if let store = library {
                let shown = items(store)
                let preview = preview
                LibraryScreen(
                    title: kind == .movie ? "Movies" : "Shows",
                    items: shown,
                    state: store.state,
                    onRetry: { store.retry() },
                    watchedIDs: watchedIDs(store),
                    session: session,
                    onRemove: { pendingRemoval = $0 },
                    onFocus: { preview.focus(PreviewSubject(item: $0)) },
                    downloads: downloads,
                    downloadPhase: downloadPhase,
                    onFocusDownload: { tile in
                        if case .detail(let item) = downloadDestination(for: tile, library: store) {
                            preview.focus(PreviewSubject(item: item))
                        }
                    })
                    .task(id: session.activeProfileID) { await store.reloadWatchStates() }
                    .libraryRemovalConfirmation(pending: $pendingRemoval,
                                                errorMessage: $removeErrorMessage,
                                                store: store)
                    .focusSection()      // let DOWN from the Movies/TV pills enter the grid and scroll it
                                          // (same fix as SettingsView / the player SettingsPanel)
                    // The first title until focus picks one, and again after a Movies/TV switch.
                    .seedsGridBackdrop(preview, key: "\(kind.rawValue)|\(shown.first?.id ?? "")",
                                       first: shown.first.map(PreviewSubject.init(item:)),
                                       contains: { id in shown.contains { $0.id == id } })
            } else {
                SeretLoader()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { GridBackdrop(preview: preview, art: art) }
    }
}

/// A horizontal strip of in-progress downloads above the library grid, so a requested title is
/// visible (with live progress) before it finishes and becomes a normal library item.
///
/// The cards are the focusable Home-rail ones, leading to the title's page. They were bare tiles:
/// nothing in the strip could take focus, so the remote skipped straight over it from the pills to
/// the grid — a download you could watch but never open, cancel or check on.
struct DownloadingStrip: View {
    let tiles: [DownloadTile]
    let library: LibraryStore?
    /// A card took focus — My Library's backdrop follows it.
    var onFocus: (DownloadTile) -> Void = { _ in }
    /// Focus arrived at (true) or left (false) the card with this id.
    var onFocusChange: (String, Bool) -> Void = { _, _ in }
    /// A card that is no longer in flight, and what became of it (nil = in flight).
    var settled: (DownloadTile) -> DownloadSettled? = { _ in nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Downloading").font(.seret(.title3, .bold))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, PosterGridLayout.rootInset)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    ForEach(tiles) { tile in
                        DownloadingRailCard(tile: tile,
                                            destination: downloadDestination(for: tile, library: library),
                                            onFocus: { onFocus(tile) },
                                            settled: settled(tile))
                        .reportsFocusChange { onFocusChange(ScrollFocusTracker.stripID(tile), $0) }
                    }
                }
                .padding(.horizontal, PosterGridLayout.rootInset)
                .padding(.vertical, 20)       // room for the card's focus lift
            }
            .scrollClipDisabled()
        }
        .frame(maxWidth: .infinity)
    }
}
