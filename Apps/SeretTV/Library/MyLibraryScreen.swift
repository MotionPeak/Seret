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
    @State private var mineOnly = false
    @State private var myKeys: Set<String> = []
    /// Which filter pill has focus. Focus only highlights; a Select press switches the kind
    /// (commit-on-press).
    @FocusState private var focusedKind: MediaKind?

    /// Show the All/Mine filter only when more than one profile exists.
    private var hasProfiles: Bool { (session.activeProfiles?.roster.count ?? 0) > 1 }

    private func items(_ store: LibraryStore) -> [MediaItem] {
        let all = kind == .movie ? store.movies : store.shows
        return (mineOnly && hasProfiles) ? all.filter { myKeys.contains($0.id) } : all
    }

    /// Finished-movie ids for the ✓ badge (movies only; a movie's content key IS its id).
    private func watchedMovieIDs(_ store: LibraryStore) -> Set<String> {
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
                if hasProfiles {
                    Divider().frame(height: 40)
                    Button("All") { mineOnly = false }
                        .buttonStyle(SeretPillStyle(selected: !mineOnly))
                    Button("Mine") { mineOnly = true }
                        .buttonStyle(SeretPillStyle(selected: mineOnly))
                }
            }
            .padding(.top, 30)
            // Commit-on-press: focus glides across the pills without switching; a click switches the
            // kind — consistent with the nav bar and the Find segments.
            .task {
                mineOnly = hasProfiles
                myKeys = Set((try? await session.myListStore?.contentKeys(
                    forProfile: session.activeProfileID ?? "")) ?? [])
            }

            if let tiles = session.downloadStore?.activeTiles, !tiles.isEmpty {
                DownloadingStrip(tiles: tiles)
            }

            if let store = session.libraryStore {
                LibraryScreen(
                    title: kind == .movie ? "Movies" : "Shows",
                    items: items(store),
                    state: store.state,
                    onRetry: { store.retry() },
                    watchedMovieIDs: watchedMovieIDs(store),
                    onRemove: { pendingRemoval = $0 },
                    onToggleWatched: { item in
                        let isWatched = store.watchByKey[item.id]?.finished == true
                        Task { await store.setWatched(!isWatched, for: item) }
                    })
                    .task(id: session.activeProfileID) { await store.reloadWatchStates() }
                    .alert("Remove \u{201C}\(pendingRemoval?.title ?? "")\u{201D}?",
                           isPresented: Binding(get: { pendingRemoval != nil },
                                                set: { if !$0 { pendingRemoval = nil } })) {
                        Button("Remove", role: .destructive) {
                            if let item = pendingRemoval { Task { await store.remove(item) } }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
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
            Text("Downloading").font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 60)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    ForEach(tiles) { DownloadingTile(tile: $0) }
                }
                .padding(.horizontal, 60)
            }
        }
    }
}

private struct DownloadingTile: View {
    let tile: DownloadTile
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                poster
                progressOverlay
            }
            .frame(width: 180, height: 270)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous))
            Text(tile.title).font(.callout).lineLimit(1)
                .frame(width: 180, alignment: .leading).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var poster: some View {
        if let url = TMDBClient.imageURL(path: tile.posterPath, size: "w500") {
            RemoteImage(url: url)
        } else {
            Theme.Palette.surface2
        }
    }

    private var progressOverlay: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                Text(label)
                Spacer()
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.white)
            ProgressView(value: tile.status.fraction)
        }
        .padding(8).background(.black.opacity(0.6))
    }

    private var label: String {
        if case .downloading = tile.status.phase { return "\(Int(tile.status.fraction * 100))%" }
        return "Queued"
    }
}
