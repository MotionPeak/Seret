import DebridCore
import DebridUI
import SwiftUI

/// Renders one library tab (Movies or Shows): an adaptive poster grid when loaded
/// (~3 columns on iPhone, ~5 on iPad via `GridItem.adaptive`), otherwise the
/// loading / empty / failed state. Mirrors the tvOS `LibraryScreen`, touch-styled.
struct LibraryGrid: View {
    let title: String
    let items: [MediaItem]
    let state: LibraryStore.State
    let onRetry: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 16)]

    var body: some View {
        switch state {
        case .loading:
            ProgressView("Loading your library…")
        case .failed(let msg):
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(msg)
            } actions: {
                Button("Try Again", action: onRetry).buttonStyle(.borderedProminent)
            }
        case .empty:
            ContentUnavailableView("Nothing in your library yet", systemImage: "tray",
                                   description: Text("Add content to your Real‑Debrid account and it appears here."))
        case .loaded:
            if items.isEmpty {
                ContentUnavailableView("No \(title.lowercased()) yet", systemImage: "tray")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(items) { PosterTile(item: $0) }
                    }
                    .padding()
                }
            }
        }
    }
}
