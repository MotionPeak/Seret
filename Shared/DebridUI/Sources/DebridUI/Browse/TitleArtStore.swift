import Foundation
import Observation
import DebridCore

/// The artwork and facts the preview header needs beyond what a tile already carries. Fetched on
/// demand from TMDB details, which ride the same call the Detail screen makes.
public struct TitleArt: Sendable, Equatable {
    public let logoPath: String?
    public let backdropPath: String?
    public let voteAverage: Double?
    public let genres: [String]
    public let runtimeMinutes: Int?
    public let seasonCount: Int?

    public init(logoPath: String?, backdropPath: String?, voteAverage: Double?, genres: [String],
                runtimeMinutes: Int?, seasonCount: Int?) {
        self.logoPath = logoPath; self.backdropPath = backdropPath; self.voteAverage = voteAverage
        self.genres = genres; self.runtimeMinutes = runtimeMinutes; self.seasonCount = seasonCount
    }
}

/// A bounded cache of `TitleArt`, shared by every screen with a preview header.
///
/// **Observed per title.** Each title's art lives in its own observable slot, so a view that read
/// one title re-renders only when THAT title's art lands. The cache used to be one observed
/// dictionary: every title Home's banner loaded invalidated every header that had read any art —
/// the kept-alive Movies, Shows and Watchlist pages behind Home included — on every title change.
/// Measured on the real Apple TV (a scripted walk along a rail): 0.6–1.3 dropped frames per focus
/// move with those pages alive, 0.03 with them gone.
///
/// The load is **store-owned**: it runs in a task the store creates, so a caller that goes away
/// (focus moved on, the view disappeared) cannot cancel a fetch another caller is waiting on, and
/// two callers for one title share a single request.
@MainActor
@Observable
public final class TitleArtStore {
    private struct Key: Hashable { let kind: MediaKind; let tmdbID: Int }

    @ObservationIgnored private let details: MediaDetailsProviding
    @ObservationIgnored private let capacity: Int
    @ObservationIgnored private var cache: [Key: TitleArt] = [:]
    /// One observable slot per title a view has asked about — see the type's doc.
    @ObservationIgnored private var slots: [Key: Slot] = [:]
    /// Least- to most-recently used.
    @ObservationIgnored private var order: [Key] = []
    @ObservationIgnored private var inFlight: [Key: Task<TitleArt?, Never>] = [:]

    public init(details: MediaDetailsProviding, capacity: Int = 300) {
        self.details = details
        self.capacity = max(1, capacity)
    }

    /// The cached art, or nil when it hasn't loaded (or failed). Synchronous, so a view can render
    /// it the moment it exists.
    public func art(for kind: MediaKind, tmdbID: Int) -> TitleArt? {
        slot(Key(kind: kind, tmdbID: tmdbID)).art
    }

    /// The title's slot, made on first ask (unobserved bookkeeping, safe inside a view's body).
    private func slot(_ key: Key) -> Slot {
        if let existing = slots[key] { return existing }
        let made = Slot(art: cache[key])
        slots[key] = made
        return made
    }

    /// Writes the cache and tells only that title's readers.
    private func store(_ art: TitleArt?, for key: Key) {
        cache[key] = art
        if let slot = slots[key] {
            if art == nil {
                slot.art = nil
                slots[key] = nil
            } else if slot.art != art {
                slot.art = art
            }
        }
    }

    /// Loads (or joins the load of) a title's art. Nil on any error; a later call retries.
    public func load(_ kind: MediaKind, tmdbID: Int) async -> TitleArt? {
        let key = Key(kind: kind, tmdbID: tmdbID)
        if let cached = cache[key] { touch(key); return cached }
        if let running = inFlight[key] { return await running.value }
        let details = details
        let task = Task { [weak self] () -> TitleArt? in
            let art = await Self.fetch(details, kind: kind, tmdbID: tmdbID)
            self?.finish(key, art)
            return art
        }
        inFlight[key] = task
        return await task.value
    }

    private func finish(_ key: Key, _ art: TitleArt?) {
        inFlight[key] = nil
        guard let art else { return }
        store(art, for: key)
        touch(key)
        while order.count > capacity {
            store(nil, for: order.removeFirst())
        }
    }

    /// Puts art another screen already holds into the cache, so a header draws it at once instead
    /// of asking TMDB again. Never replaces art the store already has.
    public func seed(_ art: TitleArt, for kind: MediaKind, tmdbID: Int) {
        let key = Key(kind: kind, tmdbID: tmdbID)
        guard cache[key] == nil else { return }
        store(art, for: key)
        touch(key)
        while order.count > capacity {
            store(nil, for: order.removeFirst())
        }
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private nonisolated static func fetch(_ details: MediaDetailsProviding, kind: MediaKind,
                                          tmdbID: Int) async -> TitleArt? {
        do {
            switch kind {
            case .movie:
                let d = try await details.movieDetails(tmdbID: tmdbID)
                return TitleArt(logoPath: d.logoPath,
                                backdropPath: d.preferredBackdropPath ?? d.backdropPath,
                                voteAverage: d.voteAverage, genres: d.genres.map(\.name),
                                runtimeMinutes: d.runtime, seasonCount: nil)
            case .show:
                let d = try await details.tvDetails(tmdbID: tmdbID)
                return TitleArt(logoPath: d.logoPath,
                                backdropPath: d.preferredBackdropPath ?? d.backdropPath,
                                voteAverage: d.voteAverage, genres: d.genres.map(\.name),
                                runtimeMinutes: nil, seasonCount: d.numberOfSeasons)
            }
        } catch {
            return nil
        }
    }
}

/// One title's art, observed on its own (see `TitleArtStore`).
@MainActor
@Observable
private final class Slot {
    var art: TitleArt?
    init(art: TitleArt?) { self.art = art }
}
