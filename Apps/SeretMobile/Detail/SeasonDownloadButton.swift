import DebridCore
import DebridUI
import SwiftUI

/// "Download Whole Season" driven by a season-pack `AddStore` (its `seasonPack` mode ranks only
/// full-season releases). Adding the best pack caches every episode at once, so bingeing / auto-
/// advance never waits between episodes. `onAdded` refreshes the library. Used by the Add screen
/// and the library show page.
struct SeasonDownloadButton: View {
    let store: AddStore?
    let onAdded: () -> Void

    var body: some View {
        if let store {
            switch store.state {
            case .idle, .loadingStreams:
                row("Checking for a full\u{2011}season pack\u{2026}", system: "square.stack.3d.up",
                    tint: Theme.Palette.textSecondary)
            case .noStreams:
                row("No full\u{2011}season version available", system: "xmark.circle",
                    tint: Theme.Palette.textSecondary)
            case .adding:
                HStack(spacing: Theme.Space.sm) {
                    ProgressView().tint(Theme.Palette.gold)
                    Text("Downloading the whole season\u{2026}")
                        .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                }
            case .added:
                row("Whole season added to your library", system: "checkmark.circle.fill", tint: .green)
            case .addFailed(let msg):
                row(msg, system: "exclamationmark.triangle", tint: .orange)
            case .failed:
                Button { Task { await store.loadStreams() } } label: {
                    Label("Check Again for a Full Season", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GhostButtonStyle())
            case .streams:
                Button {
                    Task { await store.addBest(); if case .added = store.state { onAdded() } }
                } label: {
                    Label("Download Whole Season", systemImage: "square.stack.3d.up.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GhostButtonStyle())
            case .requestingDownload, .downloading, .noDownload, .downloadFailed:
                EmptyView()   // request-download path is per-episode/movie, not season packs
            }
        }
    }

    private func row(_ text: String, system: String, tint: Color) -> some View {
        Label(text, systemImage: system).font(Theme.Typo.body()).foregroundStyle(tint)
    }
}
