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
    /// Identity for a tracked download when no cached pack exists. Nil disables that fallback.
    var showTmdbID: Int? = nil
    var season: Int = 0
    var showTitle: String = ""
    var posterPath: String? = nil
    @Environment(AppSession.self) private var session

    private var contentKey: String? {
        showTmdbID.map { DownloadKey.season(showTmdbID: $0, season: season) }
    }
    private var activeStatus: DownloadStatus? {
        contentKey.flatMap { session.downloadStore?.status(forContentKey: $0) }
    }

    var body: some View {
        if let store {
            switch store.state {
            case .idle, .loadingStreams:
                row("Checking for a full\u{2011}season pack\u{2026}", system: "square.stack.3d.up",
                    tint: Theme.Palette.textSecondary)
            case .noStreams:
                if let status = activeStatus {
                    row(DownloadProgressText.line(for: status),
                        system: "arrow.down.circle.fill", tint: Theme.Palette.gold)
                } else if contentKey != nil {
                    // Nothing cached, but RD can still fetch it — offer the tracked download
                    // rather than dead-ending here.
                    Button { Task { await startSeasonDownload() } } label: {
                        row("Download Whole Season", system: "arrow.down.circle",
                            tint: Theme.Palette.gold)
                    }
                    .buttonStyle(.plain)
                } else {
                    row("No full\u{2011}season version available", system: "xmark.circle",
                        tint: Theme.Palette.textSecondary)
                }
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
            }
        }
    }

    private func row(_ text: String, system: String, tint: Color) -> some View {
        Label(text, systemImage: system).font(Theme.Typo.body()).foregroundStyle(tint)
    }

    private func startSeasonDownload() async {
        guard let store, let key = contentKey, let tmdb = showTmdbID else { return }
        let candidates = await store.uncachedCandidates()
        guard !candidates.isEmpty else { return }
        await session.downloadStore?.request(
            contentKey: key, tmdbID: tmdb,
            title: "\(showTitle) Season \(season)",
            kind: .show, candidates: candidates, posterPath: posterPath)
    }
}
