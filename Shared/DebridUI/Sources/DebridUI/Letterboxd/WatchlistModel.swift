import Foundation
import DebridCore

public typealias WatchlistSyncRunning =
    @Sendable (_ onProgress: @Sendable @escaping (Int, Int) -> Void) async throws -> [WatchlistEntry]

/// Marks a film removed and returns the whole mirror as it now stands.
public typealias WatchlistRemoving = @Sendable (_ slug: String) async -> [WatchlistEntry]

/// Pushes pending removals to Letterboxd, reporting what happened.
public typealias WatchlistRelaying = @Sendable () async -> WatchlistRemovalRelay.Outcome

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

    /// The mirror as stored, removals included — what gets written back and carried across crawls.
    public private(set) var allEntries: [WatchlistEntry]

    /// What the owner sees. A removed film stays in the mirror (a crawl would otherwise hand it
    /// straight back) but must not appear on the screen it was removed from.
    public var entries: [WatchlistEntry] { allEntries.filter { !$0.isRemoved } }
    /// tmdbIDs the library already holds. Without this the owner is looking at a list of things to
    /// acquire that silently includes things they already have.
    public var ownedTMDBIDs: Set<Int> = []

    /// Why the last push to Letterboxd failed, if it did. Nil when there is nothing to say.
    public private(set) var relayMessage: String?

    private let settings: LetterboxdSettings
    private let minimumInterval: TimeInterval
    private let now: @Sendable () -> Date
    private let run: WatchlistSyncRunning
    private let removeSlug: WatchlistRemoving
    private let relay: WatchlistRelaying

    public init(cached: [WatchlistEntry],
                settings: LetterboxdSettings,
                minimumInterval: TimeInterval = 600,
                now: @escaping @Sendable () -> Date = { Date() },
                remove: @escaping WatchlistRemoving = { _ in [] },
                relay: @escaping WatchlistRelaying = { .idle },
                run: @escaping WatchlistSyncRunning) {
        self.allEntries = cached
        self.settings = settings
        self.minimumInterval = minimumInterval
        self.now = now
        self.run = run
        self.removeSlug = remove
        self.relay = relay
    }

    public func isOwned(_ entry: WatchlistEntry) -> Bool {
        guard let id = entry.tmdbID else { return false }
        return ownedTMDBIDs.contains(id)
    }

    /// Called when the screen appears. Opening it repeatedly should not re-crawl; the button is
    /// there for "I just added one".
    public func syncIfStale() async {
        // Always attempted, even when the crawl is skipped: a removal made while the server was
        // off is still waiting, and opening the screen is the natural moment to retry it.
        await pushRemovals()
        if let last = settings.lastImportAt, now().timeIntervalSince(last) < minimumInterval { return }
        await syncNow()
    }

    /// Takes a film off the watchlist.
    ///
    /// Marked in place, not deleted: a crawl is the whole truth about what Letterboxd holds, so an
    /// entry merely dropped here comes back on the next sync. Applied locally first so the tile
    /// goes at once — the store then confirms, and disagreement resolves in the store's favour.
    ///
    /// Letterboxd itself still lists the film. Pushing the removal there needs a write contract
    /// this app does not have yet, and the Apple TV could not post it regardless.
    public func remove(_ entry: WatchlistEntry) async {
        if let index = allEntries.firstIndex(where: { $0.slug == entry.slug }),
           allEntries[index].removedAt == nil {
            allEntries[index].removedAt = now()
        }
        let stored = await removeSlug(entry.slug)
        if !stored.isEmpty { allEntries = stored }
        await pushRemovals()
    }

    /// Tells Letterboxd about anything removed here that it has not heard about yet.
    ///
    /// Runs after a removal and when the screen opens, because the server may have been off when
    /// the removal was made. A failure is reported but changes nothing locally — the film is gone
    /// from this screen either way, and the removal stays pending for the next attempt.
    public func pushRemovals() async {
        let outcome = await relay()
        relayMessage = outcome.failed > 0 ? outcome.firstError : nil
    }

    /// A random film off the watchlist, with the reel to animate through to reach it. Nil when
    /// there is nothing eligible to land on.
    public func spin() -> WatchlistRandomizer.Spin? {
        var generator = SystemRandomNumberGenerator()
        return WatchlistRandomizer.spin(over: entries, using: &generator)
    }

    /// True when a spin has something to land on — drives whether the control is offered at all.
    public var canSpin: Bool { !WatchlistRandomizer.eligible(entries).isEmpty }

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
            allEntries = result
            phase = .idle
        } catch {
            // Deliberately keeps `allEntries`: stale beats empty, and a blank screen after a network
            // blip reads as "your watchlist is gone".
            phase = .failed(LetterboxdImportModel.message(for: error))
        }
    }
}
