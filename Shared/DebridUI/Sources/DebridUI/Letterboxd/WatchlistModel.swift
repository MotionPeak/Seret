import Foundation
import DebridCore

public typealias WatchlistSyncRunning =
    @Sendable (_ onProgress: @Sendable @escaping (Int, Int) -> Void) async throws -> [WatchlistEntry]

/// Drives the watchlist screen.
@MainActor
@Observable
public final class WatchlistModel {
    public enum Phase: Equatable, Sendable {
        case idle
        case syncing(done: Int, total: Int)
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var entries: [WatchlistEntry]
    /// tmdbIDs the library already holds. Without this the owner is looking at a list of things to
    /// acquire that silently includes things they already have.
    public var ownedTMDBIDs: Set<Int> = []

    private let settings: LetterboxdSettings
    private let minimumInterval: TimeInterval
    private let now: @Sendable () -> Date
    private let run: WatchlistSyncRunning

    public init(cached: [WatchlistEntry],
                settings: LetterboxdSettings,
                minimumInterval: TimeInterval = 600,
                now: @escaping @Sendable () -> Date = { Date() },
                run: @escaping WatchlistSyncRunning) {
        self.entries = cached
        self.settings = settings
        self.minimumInterval = minimumInterval
        self.now = now
        self.run = run
    }

    public func isOwned(_ entry: WatchlistEntry) -> Bool {
        guard let id = entry.tmdbID else { return false }
        return ownedTMDBIDs.contains(id)
    }

    /// Called when the screen appears. Opening it repeatedly should not re-crawl; the button is
    /// there for "I just added one".
    public func syncIfStale() async {
        if let last = settings.lastImportAt, now().timeIntervalSince(last) < minimumInterval { return }
        await syncNow()
    }

    /// The button. Always syncs.
    public func syncNow() async {
        guard !settings.username.isEmpty else { return }
        if case .syncing = phase { return }

        phase = .syncing(done: 0, total: 0)
        do {
            let result = try await run { [weak self] done, total in
                Task { @MainActor in
                    guard let self, case .syncing = self.phase else { return }
                    self.phase = .syncing(done: done, total: total)
                }
            }
            entries = result
            phase = .idle
        } catch {
            // Deliberately keeps `entries`: stale beats empty, and a blank screen after a network
            // blip reads as "your watchlist is gone".
            phase = .failed(LetterboxdImportModel.message(for: error))
        }
    }
}
