import DebridCore
import DebridUI
import SwiftUI

/// A focusable "Download Whole Season" control driven by a season-pack `AddStore` (its `seasonPack`
/// mode ranks only full-season releases). Selecting it adds the best cached pack — which caches
/// every episode at once — then `onAdded` refreshes the library so the episodes appear. Used by
/// both the Add screen and the library show page.
struct SeasonDownloadButton: View {
    let store: AddStore?
    let onAdded: () -> Void

    var body: some View {
        if let store {
            switch store.state {
            case .idle, .loadingStreams:
                Label("Checking for a full\u{2011}season pack\u{2026}", systemImage: "square.stack.3d.up")
                    .font(.callout).foregroundStyle(.secondary)
            case .noStreams:
                Label("No full\u{2011}season version available", systemImage: "xmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            case .adding:
                ProgressView("Downloading the whole season\u{2026}").font(.callout)
            case .added:
                Label("Whole season added to your library", systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.green)
            case .addFailed(let msg):
                Label(msg, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            case .failed:
                Button { Task { await store.loadStreams() } } label: {
                    Label("Check Again for a Full Season", systemImage: "arrow.clockwise")
                }
                .font(.title3)
            case .streams:
                Button {
                    Task { await store.addBest(); if case .added = store.state { onAdded() } }
                } label: {
                    Label("Download Whole Season", systemImage: "square.stack.3d.up.fill")
                }
                .font(.title3)
            }
        }
    }
}
