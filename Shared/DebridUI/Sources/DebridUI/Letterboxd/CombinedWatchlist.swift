import DebridCore
import Foundation

/// What a screen needs to word things about two lists it shows as one.
public struct WatchlistCombinedStatus: Sendable, Equatable {
    public let membership: WatchlistMembership
    /// Nil when there is no partner list.
    public let partnerName: String?
    /// Why the partner's list could not be read last time, in the owner's terms.
    public let partnerError: String?

    public init(membership: WatchlistMembership, partnerName: String?, partnerError: String?) {
        self.membership = membership
        self.partnerName = partnerName
        self.partnerError = partnerError
    }

    public static let solo = WatchlistCombinedStatus(membership: .empty, partnerName: nil,
                                                     partnerError: nil)
}

/// The owner's watchlist and a partner's, as the one list every screen shows.
///
/// Each list keeps its own mirror and syncer — the owner's exactly as it always was, so its
/// reconcile and push rules are untouched. The partner's syncer is never handed to a push relay,
/// and that is the whole of what makes it read-only: nothing it holds can reach Letterboxd. Hiding
/// one of the partner's films is its `removedAt` mark, carried across crawls by the same reconciler
/// that carries the owner's.
public actor CombinedWatchlist {
    private let owner: WatchlistSyncer
    private let partner: WatchlistSyncer?
    /// Read when needed rather than fixed at init: renaming the partner must not rebuild their
    /// syncer — a second actor over the same file would interleave load-mutate-saves with the first.
    private let name: @Sendable () -> String?
    private var partnerError: String?

    public init(owner: WatchlistSyncer, partner: WatchlistSyncer?,
                partnerName: @escaping @Sendable () -> String?) {
        self.owner = owner
        self.partner = partner
        self.name = partnerName
    }

    public init(owner: WatchlistSyncer, partner: WatchlistSyncer?, partnerName: String?) {
        self.init(owner: owner, partner: partner, partnerName: { partnerName })
    }

    private var partnerName: String? { partner == nil ? nil : name() }

    public func cached() async -> [WatchlistEntry] {
        WatchlistMerge.combine(owner: await owner.cached(), partner: await partner?.cached() ?? [])
    }

    /// The owner's list, then the partner's — in that order so the partner's resolver can reuse
    /// what the owner's has just matched.
    ///
    /// The two fail independently. The owner's failure is still the screen's failure, thrown as
    /// before; the partner's is recorded for a secondary line, so a private or renamed profile
    /// never puts an error over a list that is otherwise fine.
    public func sync(onProgress: (@Sendable (Int, Int) -> Void)?) async throws -> [WatchlistEntry] {
        var ownerFailure: (any Error)?
        do {
            _ = try await owner.sync(onProgress: onProgress)
        } catch {
            ownerFailure = error
        }

        if let partner {
            do {
                _ = try await partner.sync(onProgress: onProgress)
                partnerError = nil
            } catch is CancellationError {
                // Nothing to report: whoever cancelled is not waiting for a sentence.
            } catch {
                partnerError = Self.message(for: error, name: partnerName ?? "the other")
            }
        }

        if let ownerFailure { throw ownerFailure }
        return await cached()
    }

    /// Hides the film in every list holding it. Only the owner's mark can ever be pushed.
    ///
    /// Each mirror is matched by slug or TMDB id, and asked to remove ITS OWN row: a film the owner
    /// added in Seret has a placeholder slug that the partner's mirror has never heard of.
    ///
    /// The id is looked up in the mirrors themselves, not only the merged list: a screen built
    /// earlier can hold a slug the merged list no longer shows — the partner's, after the owner
    /// re-added the film and their placeholder row took over — and a removal by that slug that
    /// found no id would hide nothing and let the film straight back.
    public func remove(slug: String) async -> [WatchlistEntry] {
        let syncers = [owner] + (partner.map { [$0] } ?? [])
        var mirrors: [[WatchlistEntry]] = []
        for syncer in syncers { mirrors.append(await syncer.cached()) }
        let id = mirrors.joined().first { $0.slug == slug && $0.tmdbID != nil }?.tmdbID

        for (syncer, rows) in zip(syncers, mirrors) {
            if let row = rows.first(where: { $0.slug == slug || (id != nil && $0.tmdbID == id) }) {
                await syncer.remove(slug: row.slug)
            }
        }
        return await cached()
    }

    /// Always the owner's list: the partner's account is never written to.
    public func add(tmdbID: Int, title: String, year: Int?, posterPath: String?) async -> [WatchlistEntry] {
        await owner.add(tmdbID: tmdbID, title: title, year: year, posterPath: posterPath)
        return await cached()
    }

    public func status() async -> WatchlistCombinedStatus {
        guard let partner else { return .solo }
        return WatchlistCombinedStatus(
            membership: WatchlistMembership(owner: await owner.cached(), partner: await partner.cached()),
            partnerName: partnerName,
            partnerError: partnerError)
    }

    static func message(for error: any Error, name: String) -> String {
        switch error {
        case LetterboxdError.profileUnavailable:
            return "Couldn't read \(name)'s watchlist — the profile is private, renamed or gone."
        case LetterboxdError.structureChanged:
            return "Couldn't read \(name)'s watchlist — Letterboxd changed its page layout."
        default:
            return "Couldn't read \(name)'s watchlist. Check your connection and try again."
        }
    }
}
