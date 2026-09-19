import DebridCore
import Foundation

/// Watch state backed by the on-device store — the source of truth.
///
/// No cache, deliberately. The Trakt mirror this replaced needed a cache, a `loaded` latch and
/// cooldowns to hide
/// a network; a local store has none to hide, and porting that machinery would be inventing a
/// problem to solve.
///
/// `WatchSummaryProviding`, `WatchRatingProviding` and `ResumeFractionProviding` take no
/// `profileID` — they were written when Trakt gave everyone one shared history. Hence the resolver
/// closure, the same shape `AppSession` already passes to `LibraryStore` and `DetailStore`.
public struct LocalWatchProvider: WatchProgressProviding, Sendable {
    private let store: LocalWatchStore
    /// Main-actor isolated because the active profile lives on `AppSession`, which is `@MainActor`.
    /// Every caller below is already `async`, so awaiting the hop costs nothing.
    private let profileID: @MainActor @Sendable () -> String
    /// Optional so every existing construction site compiles unchanged, and so the app runs
    /// normally with no server configured — the push is an extra, not a dependency.
    private let push: LetterboxdPushCoordinator?

    public init(store: LocalWatchStore,
                profileID: @escaping @MainActor @Sendable () -> String,
                push: LetterboxdPushCoordinator? = nil) {
        self.store = store
        self.profileID = profileID
        self.push = push
    }

    /// Fraction of runtime past which a title counts as watched. One definition, in `WatchState`:
    /// `resumePosition` needs the same number to tell a position reached by watching from one a
    /// manual mark carried forward.
    public static var finishedFraction: Double { WatchState.finishedFraction }

    /// Hand rows recorded before a profile resolved to `owner` — see
    /// `LocalWatchStore.adoptUnprofiledProgress`. Idempotent; runs once per launch.
    public func adoptUnprofiledProgress(into owner: String) async throws {
        try await store.adoptUnprofiledProgress(into: owner)
    }

    public func progress(forContentKey key: String, profileID: String) async throws -> WatchState? {
        try await store.state(forContentKey: key, profileID: profileID)
    }

    public func progress(forContentKeys keys: [String],
                         profileID: String) async throws -> [String: WatchState] {
        try await store.states(forContentKeys: keys, profileID: profileID)
    }

    public func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                       durationSeconds: Double, finished: Bool, profileID: String) async throws {
        // Duration 0 means a manual mark, which carries no position — computing a fraction there
        // would divide by zero. Only real playback can cross the threshold.
        let reachedEnd = durationSeconds > 0
            && positionSeconds / durationSeconds >= Self.finishedFraction
        let crossedIntoFinished = try await store.write(
            contentKey: contentKey, sourceKey: sourceKey,
            positionSeconds: positionSeconds, durationSeconds: durationSeconds,
            finished: finished || reachedEnd, profileID: profileID)

        // Only on the edge, so re-saving position on an already watched film cannot file a second
        // diary entry for one viewing. The rating and play count are read back rather than passed
        // in: the store has just collapsed any CloudKit duplicates, so it is the only place they
        // are right.
        guard crossedIntoFinished, let push else { return }
        // `rollup` returns an optional tuple, so the count is unwrapped before it is read; a film
        // with no row is a first viewing by definition.
        let rating = try? await store.rating(forContentKey: contentKey, profileID: profileID)
        let rollup = try? await store.rollup(forContentKey: contentKey, profileID: profileID)
        await push.recordFinish(contentKey: contentKey, rating: rating ?? nil,
                                plays: rollup?.plays ?? 1, at: Date())
    }

    public func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] {
        try await store.recent(limit: limit, profileID: profileID)
    }

    public func deleteProgress(forContentKeys keys: [String]) async throws {
        try await store.delete(contentKeys: keys)
    }
}

extension LocalWatchProvider: WatchSummaryProviding {
    public func watchSummary(forContentKey key: String) async -> WatchSummary? {
        guard let rollup = try? await store.rollup(forContentKey: key, profileID: await profileID())
        else { return nil }
        return WatchSummary(plays: rollup.plays, lastWatchedAt: rollup.lastWatchedAt)
    }

    /// Local history only knows what it recorded. Nil until this title has been finished once —
    /// it does not pretend to know about viewing that happened before the store existed.
    ///
    /// One unwrap, not two: `try?` flattens rather than producing `Date??`, so the store's
    /// already-optional return needs no second `let`.
    public func historySince(forContentKey key: String) async -> Date? {
        guard let rollup = try? await store.rollup(forContentKey: key, profileID: await profileID())
        else { return nil }
        return rollup.lastWatchedAt
    }
}

extension LocalWatchProvider: WatchRatingProviding {
    public func rating(forContentKey key: String) async -> Int? {
        try? await store.rating(forContentKey: key, profileID: await profileID())
    }

    public func setRating(_ value: Int?, forContentKey key: String) async {
        try? await store.setRating(value, contentKey: key, profileID: await profileID())
    }
}
