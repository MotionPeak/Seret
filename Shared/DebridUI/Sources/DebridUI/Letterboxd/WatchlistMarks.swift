import DebridCore
import Foundation
import Observation

/// A film as a screen knows it, which is all an add needs.
///
/// Letterboxd is films-only, so there is deliberately no way to build one of these from a show.
public struct WatchlistFilm: Sendable, Equatable {
    public let tmdbID: Int
    public let title: String
    public let year: Int?
    public let posterPath: String?

    public init(tmdbID: Int, title: String, year: Int?, posterPath: String?) {
        self.tmdbID = tmdbID
        self.title = title
        self.year = year
        self.posterPath = posterPath
    }

    /// Nil for a show, and nil for a movie with no TMDB id — the push resolves a film by that id,
    /// so without one there is nothing to send.
    public init?(item: MediaItem) {
        guard item.kind == .movie, let tmdbID = item.tmdbID else { return nil }
        self.init(tmdbID: tmdbID, title: item.title, year: item.year, posterPath: item.posterPath)
    }

    /// Nil for a show. A search result always carries an id.
    public init?(hit: SearchHit) {
        guard hit.kind == .movie else { return nil }
        self.init(tmdbID: hit.result.id, title: hit.result.displayTitle,
                  year: hit.result.year, posterPath: hit.result.posterPath)
    }
}

/// The mirror, read fresh. Every write hands back the whole thing, so one shape serves both.
public typealias WatchlistMirrorReading = @Sendable () async -> [WatchlistEntry]
public typealias WatchlistFilmAdding = @Sendable (_ film: WatchlistFilm) async -> [WatchlistEntry]

/// Which films are on the watchlist, and the one control that changes it.
///
/// Shared by every surface that offers the toggle — browse tiles, search tiles, the title page — so
/// a film added on one is marked on all of them without a re-read. A sibling to `TileWatchMarks`
/// rather than part of it: that answers "has this been watched", from local watch state, and this
/// answers "is this on Letterboxd's watchlist" and writes to it.
@MainActor
@Observable
public final class WatchlistMarks {
    /// What the last change asked for, and what became of it.
    public struct Outcome: Sendable, Equatable {
        public let tmdbID: Int
        /// The direction asked for, so a view can tell "added" from "removed" without parsing text.
        public let added: Bool
        public let message: String
        public let isFailure: Bool
        /// New on every change, including a repeat of the same film in the same direction — a view
        /// watching the id alone would see nothing happen the second time.
        public let event: UUID

        public init(tmdbID: Int, added: Bool, message: String, isFailure: Bool,
                    event: UUID = UUID()) {
            self.tmdbID = tmdbID
            self.added = added
            self.message = message
            self.isFailure = isFailure
            self.event = event
        }
    }

    private var onWatchlist: Set<Int> = []
    /// The mirror's row per film. The slug is what a removal must name — guessing the placeholder
    /// for a crawled film hits no row at all — and the pending marks are what say whether a change
    /// is a Letterboxd write or a purely local one.
    private var rows: [Int: WatchlistEntry] = [:]
    public private(set) var lastOutcome: Outcome?
    /// Films whose write is in flight, so a control can stay quiet rather than firing twice.
    public private(set) var inFlight: Set<Int> = []

    private let entries: WatchlistMirrorReading
    private let addFilm: WatchlistFilmAdding
    private let removeSlug: WatchlistRemoving
    private let relay: WatchlistRelaying

    public init(entries: @escaping WatchlistMirrorReading,
                add: @escaping WatchlistFilmAdding,
                remove: @escaping WatchlistRemoving,
                relay: @escaping WatchlistRelaying) {
        self.entries = entries
        self.addFilm = add
        self.removeSlug = remove
        self.relay = relay
    }

    /// Inert, for the single render before the shell's real object exists. Static so a body
    /// re-evaluation does not allocate and discard one on every pass.
    public static let placeholder = WatchlistMarks(entries: { [] }, add: { _ in [] },
                                                   remove: { _ in [] }, relay: { .idle })

    public func contains(tmdbID: Int) -> Bool { onWatchlist.contains(tmdbID) }
    public func isInFlight(tmdbID: Int) -> Bool { inFlight.contains(tmdbID) }

    /// Reads the mirror from disk. No network — a crawl is the watchlist screen's job.
    public func load() async {
        absorb(await entries())
    }

    /// Puts the film on the watchlist or takes it off, and tells Letterboxd.
    ///
    /// The mark flips first: a long-press that looked unchanged for a beat is a long-press the owner
    /// repeats, which toggles it straight back. The store then confirms, and disagreement resolves
    /// in the store's favour — a screen that claims a change the mirror refused is lying about what
    /// it holds.
    public func toggle(film: WatchlistFilm) async {
        guard !inFlight.contains(film.tmdbID) else { return }
        let wanted = !contains(tmdbID: film.tmdbID)
        // Read BEFORE the write, because the write is what destroys the evidence: a removal that
        // cancels an unsent add deletes the row outright, leaving nothing behind to say that
        // Letterboxd was never involved.
        let cancelsAnUnsentChange = Self.cancels(rows[film.tmdbID], byAsking: wanted)

        inFlight.insert(film.tmdbID)
        defer { inFlight.remove(film.tmdbID) }
        if wanted { onWatchlist.insert(film.tmdbID) } else { onWatchlist.remove(film.tmdbID) }

        let stored: [WatchlistEntry]
        if wanted {
            stored = await addFilm(film)
        } else {
            // The mirror's own slug where there is one. The placeholder is the fallback rather than
            // the default: a crawled film's row is keyed by the slug Letterboxd knows.
            stored = await removeSlug(rows[film.tmdbID]?.slug
                ?? WatchlistEntry.localSlug(forTMDB: film.tmdbID))
        }
        absorb(stored)

        let outcome = await relay()
        // Re-read, because whether the change actually reached Letterboxd is a fact about the mirror
        // now: the relay clears the pending mark when the server accepts it.
        let settled = await entries()
        absorb(settled)
        record(outcome, for: film, added: wanted, mirror: settled,
               cancelled: cancelsAnUnsentChange)
    }

    private func absorb(_ mirror: [WatchlistEntry]) {
        onWatchlist = Set(mirror.filter { !$0.isRemoved }.compactMap(\.tmdbID))
        rows = Dictionary(mirror.compactMap { entry in entry.tmdbID.map { ($0, entry) } },
                          uniquingKeysWith: { first, _ in first })
    }

    /// Says what happened in the owner's terms, which is three different sentences.
    /// Whether asking for `added` merely takes back a change that never reached Letterboxd.
    ///
    /// Both directions: removing a film whose add never went out, and re-adding one whose removal
    /// never went out. Either way the two cancel, nothing is sent, and nothing may be claimed.
    private static func cancels(_ row: WatchlistEntry?, byAsking added: Bool) -> Bool {
        guard let row else { return false }
        return added ? row.needsRemovalPush : row.needsAddPush
    }

    private func record(_ outcome: WatchlistPushRelay.Outcome, for film: WatchlistFilm,
                        added: Bool, mirror: [WatchlistEntry], cancelled: Bool) {
        let verb = added ? "Added to" : "Removed from"

        // The mirror does not reflect what was asked, so the change did not take at all — and there
        // is nothing true to say about a write that never happened. Silence beats a sentence
        // describing someone else's outcome.
        guard contains(tmdbID: film.tmdbID) == added else { return }

        // The two halves cancelled, so nothing of this film's was in that drain — a failure it
        // reports belongs to some other film, and naming Letterboxd here would describe a write
        // that never happened.
        if cancelled {
            lastOutcome = Outcome(tmdbID: film.tmdbID, added: added,
                                  message: "\(verb) your watchlist", isFailure: false)
            return
        }

        if let error = outcome.firstError, outcome.failed > 0 {
            lastOutcome = Outcome(tmdbID: film.tmdbID, added: added, message: error, isFailure: true)
            return
        }

        // Nothing was refused, but the change may not have gone anywhere either: with no server
        // configured, or none reachable, the relay has nothing to report and the mirror still holds
        // the change as pending.
        let row = mirror.first { $0.tmdbID == film.tmdbID }
        let stillPending = added ? (row?.needsAddPush ?? false) : (row?.needsRemovalPush ?? false)
        if stillPending {
            lastOutcome = Outcome(tmdbID: film.tmdbID, added: added,
                                  message: "\(verb) your watchlist — Letterboxd hasn't been told yet",
                                  isFailure: false)
            return
        }

        lastOutcome = Outcome(tmdbID: film.tmdbID, added: added,
                              message: "\(verb) your Letterboxd watchlist", isFailure: false)
    }
}
