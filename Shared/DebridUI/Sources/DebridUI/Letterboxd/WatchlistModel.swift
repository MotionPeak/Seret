import Foundation
import DebridCore

public typealias WatchlistSyncRunning =
    @Sendable (_ onProgress: @Sendable @escaping (Int, Int) -> Void) async throws -> [WatchlistEntry]

/// Marks a film removed and returns the whole mirror as it now stands.
public typealias WatchlistRemoving = @Sendable (_ slug: String) async -> [WatchlistEntry]

/// Pushes pending watchlist changes to Letterboxd, reporting what happened.
public typealias WatchlistRelaying = @Sendable () async -> WatchlistPushRelay.Outcome

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
    /// Asks the library directly, so ownership is current — `ownedTMDBIDs` was a copy taken when
    /// the model was built, which on tvOS is at launch, before the library has even been read: the
    /// gold "in your library" check never appeared. Wins over `ownedTMDBIDs` when set.
    @ObservationIgnored public var ownedLookup: (@MainActor (Int) -> Bool)?

    /// Why the last push to Letterboxd failed, if it did. Nil when there is nothing to say.
    public private(set) var relayMessage: String?

    /// Whose list each film is on, and whether the partner's list could be read. The grid never
    /// shows it — the two lists are one list on screen — but a removal has to be worded by it.
    public private(set) var combinedStatus: WatchlistCombinedStatus = .solo

    /// Why the partner's list could not be read, if it could not. A secondary line, never
    /// `.failed`: the owner's list is fine, and an error over it would say otherwise.
    public var partnerMessage: String? { combinedStatus.partnerError }

    private let settings: LetterboxdSettings
    private let minimumInterval: TimeInterval
    private let now: @Sendable () -> Date
    private let run: WatchlistSyncRunning
    /// The crawl in flight, owned here rather than by whoever asked — see `syncNow()`.
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    private let removeSlug: WatchlistRemoving
    private let relay: WatchlistRelaying
    private let status: @Sendable () async -> WatchlistCombinedStatus

    public init(cached: [WatchlistEntry],
                settings: LetterboxdSettings,
                minimumInterval: TimeInterval = 600,
                now: @escaping @Sendable () -> Date = { Date() },
                remove: @escaping WatchlistRemoving = { _ in [] },
                relay: @escaping WatchlistRelaying = { .idle },
                status: @escaping @Sendable () async -> WatchlistCombinedStatus = { .solo },
                run: @escaping WatchlistSyncRunning) {
        self.allEntries = cached
        self.settings = settings
        self.minimumInterval = minimumInterval
        self.now = now
        self.run = run
        self.removeSlug = remove
        self.relay = relay
        self.status = status
    }

    /// Re-reads whose list each film is on. Cheap — two small files, no network.
    public func refreshStatus() async {
        combinedStatus = await status()
    }

    /// The confirmation's sentence for taking `entry` off the list.
    ///
    /// Only the owner's Letterboxd can be written to, so a partner's film is hidden here and stays
    /// on their list — and the owner should be told that before agreeing, not after.
    public func removalMessage(for entry: WatchlistEntry) -> String {
        let title = WatchlistName.stripYear(from: entry.name)
        let fromOwners = "\(title) will be removed from your Letterboxd watchlist."
        guard let name = combinedStatus.partnerName else { return fromOwners }
        let held = combinedStatus.membership.holders(of: entry)
        switch (held.owner, held.partner) {
        case (false, true):
            return "\(title) will be hidden in Seret. It stays on \(name)'s Letterboxd watchlist."
        case (true, true):
            return "\(fromOwners) It stays on \(name)'s, hidden here."
        default:
            return fromOwners
        }
    }

    public func isOwned(_ entry: WatchlistEntry) -> Bool {
        guard let id = entry.tmdbID else { return false }
        if let ownedLookup { return ownedLookup(id) }
        return ownedTMDBIDs.contains(id)
    }

    /// Called when the screen appears. Opening it repeatedly should not re-crawl; the button is
    /// there for "I just added one".
    public func syncIfStale() async {
        // Always attempted, even when the crawl is skipped: a change made while the server was
        // off is still waiting, and opening the screen is the natural moment to retry it.
        await pushPending()
        // Before the stale gate: a fresh list skips the crawl, and the screen still has to word a
        // removal by whose list a film is on.
        await refreshStatus()
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
        await refreshStatus()
        await pushPending()
    }

    /// Tells Letterboxd about anything changed here that it has not heard about yet — removals
    /// made on this screen, and adds made on a title page or a tile.
    ///
    /// Runs after a removal and when the screen opens, because the server may have been off when
    /// the change was made. A failure is reported but changes nothing locally — the screen already
    /// shows what was asked for, and the change stays pending for the next attempt.
    public func pushPending() async {
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

    /// The button. Always syncs — or joins the sync already running.
    ///
    /// The crawl runs in a task the MODEL owns. It used to run in the caller's: the screen's
    /// `.task`, which a push cancels (opening a film makes the Watchlist disappear). The cancelled
    /// crawl came back as an error, so returning showed "Import failed" over a list that had been
    /// fine, and the next appearance crawled Letterboxd all over again.
    public func syncNow() async {
        if let syncTask { await syncTask.value; return }
        guard !settings.username.isEmpty else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performSync()
        }
        syncTask = task
        await task.value
        syncTask = nil
    }

    private func performSync() async {
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
            await refreshStatus()
        } catch {
            // Deliberately keeps `allEntries`: stale beats empty, and a blank screen after a network
            // blip reads as "your watchlist is gone".
            phase = .failed(LetterboxdImportModel.message(for: error))
            await refreshStatus()
        }
    }
}
