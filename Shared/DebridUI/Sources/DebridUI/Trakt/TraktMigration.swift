import DebridCore
import Foundation

/// One-time hand-off of locally-recorded watch progress to Trakt.
///
/// Runs once per device, the first time a Trakt account is linked on a build that has Trakt as the
/// watch-state source of truth. Finished titles become history; part-watched ones become a paused
/// scrobble so they still show up in Continue Watching.
///
/// Old rows carry a `contentKey` that already encodes the TMDB identity
/// (`movie:tmdb:…` / `show:tmdb:…:sNeN`), so no library lookup is needed — rows whose key predates
/// TMDB enrichment simply have no Trakt identity and are skipped.
public enum TraktMigration {
    public struct Row: Sendable, Equatable {
        public let ref: TraktMediaRef
        public let fraction: Double
        public let finished: Bool
        public init(ref: TraktMediaRef, fraction: Double, finished: Bool) {
            self.ref = ref
            self.fraction = fraction
            self.finished = finished
        }
    }

    /// Convert stored watch states into migratable rows, dropping anything without a Trakt identity
    /// and anything with no progress worth carrying over.
    public static func rows(from states: [WatchState]) -> [Row] {
        states.compactMap { state in
            guard let ref = TraktMapping.ref(forContentKey: state.contentKey) else { return nil }
            let fraction = state.durationSeconds > 0
                ? min(1, max(0, state.positionSeconds / state.durationSeconds)) : 0
            guard state.finished || fraction > 0 else { return nil }
            return Row(ref: ref, fraction: fraction, finished: state.finished)
        }
    }

    /// Push rows to Trakt. Finished titles go to history in one batched call; part-watched ones are
    /// paused-scrobbled individually (that is what creates a resume point). Best-effort throughout —
    /// a migration failure must never block sign-in.
    public static func push(_ rows: [Row], to api: TraktWatchAPI) async throws {
        let finished = rows.filter(\.finished).map(\.ref)
        if !finished.isEmpty { try await api.addToHistory(finished) }
        for row in rows where !row.finished {
            try? await api.scrobble(.pause, ref: row.ref,
                                    progress: max(0, min(100, row.fraction * 100)))
        }
    }
}
