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
    @State private var mineOnly = false
    @State private var myKeys: Set<String> = []

    /// Show the All/Mine filter only when more than one profile exists.
    private var hasProfiles: Bool { (session.activeProfiles?.roster.count ?? 0) > 1 }

    private func items(_ store: LibraryStore) -> [MediaItem] {
        let all = kind == .movie ? store.movies : store.shows
        return (mineOnly && hasProfiles) ? all.filter { myKeys.contains($0.id) } : all
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

                if hasProfiles {
                    Picker("Scope", selection: $mineOnly) {
                        Text("All").tag(false)
                        Text("Mine").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.Space.lg)
                }

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
                        onRemove: { pendingRemoval = $0 })
                        .task(id: store.attempt) { await store.load() }
                        .task {
                            mineOnly = hasProfiles
                            myKeys = Set((try? await session.myListStore?.contentKeys(
                                forProfile: session.activeProfileID ?? "")) ?? [])
                        }
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

private struct DownloadingTile: View {
    let tile: DownloadTile
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                poster
                progressOverlay
            }
            .frame(width: 100, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip))
            Text(tile.title).font(Theme.Typo.caption()).lineLimit(1)
                .frame(width: 100, alignment: .leading).foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    @ViewBuilder private var poster: some View {
        if let url = TMDBClient.imageURL(path: tile.posterPath, size: "w300") {
            AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                placeholder: { Rectangle().fill(.gray.opacity(0.25)) }
        } else {
            Rectangle().fill(.gray.opacity(0.25))
        }
    }

    private var progressOverlay: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                Text(label)
                Spacer()
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(.white)
            ProgressView(value: tile.status.fraction).tint(Theme.Palette.gold)
        }
        .padding(6)
        .background(.black.opacity(0.55))
    }

    private var label: String {
        if case .downloading = tile.status.phase { return "\(Int(tile.status.fraction * 100))%" }
        return "Queued"
    }
}
