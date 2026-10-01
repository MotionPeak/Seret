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
            // ONE button whose label follows the state — never a switch between a Button and a
            // plain label. Pressing "Download Whole Season" used to turn the FOCUSED button into a
            // ProgressView, and tvOS answers a focused view being replaced by dropping focus to the
            // top of the page. A press while there is nothing to do is simply ignored.
            let shown = presentation(for: store)
            Button { shown.action?() } label: {
                Label(shown.title, systemImage: shown.icon)
            }
            .buttonStyle(SeretActionButtonStyle())
        }
    }

    private struct Presentation {
        let title: String
        let icon: String
        /// nil = a status, not an action: the press does nothing.
        let action: (() -> Void)?
    }

    private func presentation(for store: AddStore) -> Presentation {
        switch store.state {
        case .idle, .loadingStreams:
            return Presentation(title: "Checking for a full\u{2011}season pack\u{2026}",
                                icon: "square.stack.3d.up", action: nil)
        case .noStreams:
            if let status = activeStatus {
                return Presentation(title: DownloadProgressText.line(for: status),
                                    icon: "arrow.down.circle.fill", action: nil)
            }
            if contentKey != nil {
                // Nothing cached, but RD can still fetch it — offer the tracked download rather
                // than dead-ending here.
                return Presentation(title: "Download Whole Season", icon: "arrow.down.circle",
                                    action: { Task { await startSeasonDownload() } })
            }
            return Presentation(title: "No full\u{2011}season version available",
                                icon: "xmark.circle", action: nil)
        case .adding:
            return Presentation(title: "Adding the whole season\u{2026}", icon: "hourglass", action: nil)
        case .added:
            return Presentation(title: "Whole season added to your library",
                                icon: "checkmark.circle.fill", action: nil)
        case .addFailed(let message):
            // Pressing again looks for a pack afresh rather than leaving a dead end.
            return Presentation(title: message, icon: "exclamationmark.triangle",
                                action: { Task { await store.loadStreams() } })
        case .failed:
            return Presentation(title: "Check Again for a Full Season", icon: "arrow.clockwise",
                                action: { Task { await store.loadStreams() } })
        case .streams:
            return Presentation(title: "Download Whole Season", icon: "square.stack.3d.up.fill",
                                action: {
                                    Task { await store.addBest(); if case .added = store.state { onAdded() } }
                                })
        }
    }

    private func startSeasonDownload() async {
        guard let store, let tmdb = showTmdbID else { return }
        let candidates = await store.uncachedCandidates()
        guard !candidates.isEmpty else { return }
        let target = DownloadTarget(contentKey: DownloadKey.season(showTmdbID: tmdb, season: season),
                                    tmdbID: tmdb, title: "\(showTitle) Season \(season)", kind: .show,
                                    posterPath: posterPath)
        await session.downloadStore?.request(target, candidates: candidates)
    }
}
