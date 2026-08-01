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
                Label("Checking for a full\u{2011}season pack\u{2026}", systemImage: "square.stack.3d.up")
                    .font(.seretCallout).foregroundStyle(.secondary)
            case .noStreams:
                if let status = activeStatus {
                    Label(DownloadProgressText.line(for: status),
                          systemImage: "arrow.down.circle.fill")
                        .font(.seretCallout).foregroundStyle(.secondary)
                } else if contentKey != nil {
                    // Nothing cached, but RD can still fetch it — offer the tracked download
                    // rather than dead-ending here.
                    Button { Task { await startSeasonDownload() } } label: {
                        Label("Download Whole Season", systemImage: "arrow.down.circle")
                    }
                    .font(.seretTitle3)
                } else {
                    Label("No full\u{2011}season version available", systemImage: "xmark.circle")
                        .font(.seretCallout).foregroundStyle(.secondary)
                }
            case .adding:
                ProgressView("Adding the whole season\u{2026}").font(.seretCallout)
            case .added:
                Label("Whole season added to your library", systemImage: "checkmark.circle.fill")
                    .font(.seretCallout).foregroundStyle(.green)
            case .addFailed(let msg):
                Label(msg, systemImage: "exclamationmark.triangle").font(.seretCallout).foregroundStyle(.orange)
            case .failed:
                Button { Task { await store.loadStreams() } } label: {
                    Label("Check Again for a Full Season", systemImage: "arrow.clockwise")
                }
                .font(.seretTitle3)
            case .streams:
                Button {
                    Task { await store.addBest(); if case .added = store.state { onAdded() } }
                } label: {
                    Label("Download Whole Season", systemImage: "square.stack.3d.up.fill")
                }
                .font(.seretTitle3)
            }
        }
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
