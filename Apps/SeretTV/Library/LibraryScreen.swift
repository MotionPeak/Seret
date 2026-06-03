import DebridCore
import SwiftUI

/// Renders one tab (Movies or Shows): the poster grid when loaded, otherwise the
/// loading / empty / failed state. `items` is the kind-filtered slice from the store;
/// `state` is the store's overall load state.
struct LibraryScreen: View {
    let title: String
    let items: [MediaItem]
    let state: LibraryStore.State
    let onRetry: () -> Void

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(title)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            ProgressView("Loading your library…").font(.title3)
        case .failed(let msg):
            message(msg, systemImage: "exclamationmark.triangle", action: ("Try Again", onRetry))
        case .empty:
            message("Nothing in your Real‑Debrid library yet.", systemImage: "tray", action: nil)
        case .loaded:
            if items.isEmpty {
                message("No \(title.lowercased()) yet.", systemImage: "tray", action: nil)
            } else {
                PosterGrid(items: items)
            }
        }
    }

    private func message(_ text: String, systemImage: String,
                         action: (label: String, run: () -> Void)?) -> some View {
        VStack(spacing: 28) {
            Image(systemName: systemImage).font(.system(size: 64)).foregroundStyle(.secondary)
            Text(text).font(.title3).multilineTextAlignment(.center).frame(maxWidth: 700)
            if let action {
                Button(action.label, action: action.run).font(.title3)
            }
        }
    }
}
