#if canImport(SwiftData)
import Foundation

/// Bridges playback to `WatchProgressStore`: where to resume a title, and saving progress as it
/// plays. Stateless and `Sendable` — the app drives it (calls `record` on a timer / pause /
/// background), so throttling lives in the app and the coordinator stays decoupled from the
/// engine's callbacks. Saves are best-effort: a store error never interrupts playback.
public struct PlaybackCoordinator: Sendable {
    private let store: WatchProgressStore
    private let finishedThreshold: Double
    private let profileID: String

    public init(store: WatchProgressStore, profileID: String, finishedThreshold: Double = 0.95) {
        self.store = store
        self.profileID = profileID
        self.finishedThreshold = finishedThreshold
    }

    /// The position to resume a title from — `0` if there's no saved progress for this profile, the
    /// title is already finished, or the lookup fails.
    public func resumePosition(contentKey: String) async -> Double {
        guard let state = (try? await store.progress(forContentKey: contentKey,
                                                     profileID: profileID)) ?? nil,
              !state.finished else { return 0 }
        return state.positionSeconds
    }

    /// Persist the current position for this profile (best-effort), marking the title finished once
    /// `position / duration >= finishedThreshold`.
    public func record(contentKey: String, sourceKey: String,
                       position: Double, duration: Double) async {
        let finished = duration > 0 && position / duration >= finishedThreshold
        try? await store.record(contentKey: contentKey, sourceKey: sourceKey,
                                positionSeconds: position, durationSeconds: duration,
                                finished: finished, profileID: profileID)
    }
}
#endif
