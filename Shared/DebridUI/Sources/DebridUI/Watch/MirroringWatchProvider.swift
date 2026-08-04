import DebridCore
import Foundation

/// Local watch state is the truth; Trakt is a mirror that receives writes when it is linked.
///
/// Reads never touch Trakt. That is the entire point: when Trakt is unreachable — throttled,
/// unlinked, or its API app deleted out from under us — Continue Watching, Resume and the watched
/// checkmark keep working, because nothing on a read path depends on it.
public struct MirroringWatchProvider: WatchProgressProviding, Sendable {
    private let local: any LocalWatchBacking
    private let trakt: (any TraktWatchBacking)?
    /// Whether the active profile is the one that linked Trakt. Several profiles share one Trakt
    /// account, so only that profile's viewing is mirrored outward.
    private let shouldMirror: @Sendable () -> Bool

    public init(local: any LocalWatchBacking, trakt: (any TraktWatchBacking)?,
                shouldMirror: @escaping @Sendable () -> Bool) {
        self.local = local
        self.trakt = trakt
        self.shouldMirror = shouldMirror
    }

    /// The Trakt side of a write: detached, and its errors are swallowed. A mirror failure must
    /// never reach the caller, because the caller is usually playback.
    private func mirror(_ body: @escaping @Sendable (any TraktWatchBacking) async -> Void) {
        guard shouldMirror(), let trakt else { return }
        Task { await body(trakt) }
    }

    // MARK: Reads — local only

    public func progress(forContentKey key: String, profileID: String) async throws -> WatchState? {
        try await local.progress(forContentKey: key, profileID: profileID)
    }

    public func progress(forContentKeys keys: [String],
                         profileID: String) async throws -> [String: WatchState] {
        try await local.progress(forContentKeys: keys, profileID: profileID)
    }

    public func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] {
        try await local.recentlyWatched(limit: limit, profileID: profileID)
    }

    // MARK: Writes — local first and awaited, then Trakt best-effort

    public func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                       durationSeconds: Double, finished: Bool, profileID: String) async throws {
        try await local.record(contentKey: contentKey, sourceKey: sourceKey,
                               positionSeconds: positionSeconds, durationSeconds: durationSeconds,
                               finished: finished, profileID: profileID)
        mirror { trakt in
            try? await trakt.record(contentKey: contentKey, sourceKey: sourceKey,
                                    positionSeconds: positionSeconds,
                                    durationSeconds: durationSeconds,
                                    finished: finished, profileID: profileID)
        }
    }

    public func deleteProgress(forContentKeys keys: [String]) async throws {
        try await local.deleteProgress(forContentKeys: keys)
        // Trakt's implementation only clears its in-memory cache — it does not touch the user's
        // Trakt history, which is correct: the title left OUR library, not their viewing record.
        mirror { trakt in try? await trakt.deleteProgress(forContentKeys: keys) }
    }
}

extension MirroringWatchProvider: WatchSummaryProviding {
    public func watchSummary(forContentKey key: String) async -> WatchSummary? {
        await local.watchSummary(forContentKey: key)
    }

    public func historySince(forContentKey key: String) async -> Date? {
        await local.historySince(forContentKey: key)
    }
}

extension MirroringWatchProvider: WatchRatingProviding {
    public func rating(forContentKey key: String) async -> Int? {
        await local.rating(forContentKey: key)
    }

    public func setRating(_ value: Int?, forContentKey key: String) async {
        await local.setRating(value, forContentKey: key)
        mirror { trakt in await trakt.setRating(value, forContentKey: key) }
    }
}

extension MirroringWatchProvider: ResumeFractionProviding {
    public func resumeFraction(forContentKey key: String) async -> Double? {
        await local.resumeFraction(forContentKey: key)
    }
}

extension MirroringWatchProvider: CommunityRatingProviding {
    /// The only capability that routes to Trakt: a global average is not something a local store
    /// can invent. Nil when Trakt is absent, and the title page hides the chip.
    public func communityRating(imdbID: String, kind: MediaKind) async -> Double? {
        await trakt?.communityRating(imdbID: imdbID, kind: kind)
    }
}
