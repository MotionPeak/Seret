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
    /// Which filter pill has focus — moving between them switches the list live (no press).
    @FocusState private var focusedKind: MediaKind?

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
            .onChange(of: focusedKind) { _, new in if let new { kind = new } }

            if let tiles = session.downloadStore?.activeTiles, !tiles.isEmpty {
                DownloadingStrip(tiles: tiles)
            }

            if let store = session.libraryStore {
                LibraryScreen(
                    title: kind == .movie ? "Movies" : "Shows",
                    items: kind == .movie ? store.movies : store.shows,
                    state: store.state,
                    onRetry: { store.retry() },
                    onRemove: { pendingRemoval = $0 })
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
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(tile.title).font(.callout).lineLimit(1)
                .frame(width: 180, alignment: .leading).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var poster: some View {
        if let url = TMDBClient.imageURL(path: tile.posterPath, size: "w500") {
            AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                placeholder: { Rectangle().fill(.gray.opacity(0.25)) }
        } else {
            Rectangle().fill(.gray.opacity(0.25))
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
