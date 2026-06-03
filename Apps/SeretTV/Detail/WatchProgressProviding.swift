import DebridCore
import Foundation

/// Sendable seam over `WatchProgressStore` so `DetailStore` reads/writes progress without
/// pulling SwiftData into the app's unit tests.
protocol WatchProgressProviding: Sendable {
    func progress(forContentKey key: String) async throws -> WatchState?
    func record(contentKey: String, sourceKey: String,
                positionSeconds: Double, durationSeconds: Double, finished: Bool) async throws
}

extension WatchProgressStore: WatchProgressProviding {
    // `progress(forContentKey:)` already satisfies the requirement (actor-isolated witness).
    // Provide the no-`at:` overload the seam declares; stamp the time here.
    public func record(contentKey: String, sourceKey: String,
                       positionSeconds: Double, durationSeconds: Double, finished: Bool) throws {
        try record(contentKey: contentKey, sourceKey: sourceKey,
                   positionSeconds: positionSeconds, durationSeconds: durationSeconds,
                   finished: finished, at: Date())
    }
}
