import Foundation
import DebridCore

/// Picks a film off the watchlist at random, and builds the reel the spinner animates through.
///
/// Pure, and seeded through an injected generator, so a spin's outcome is a fact a test can assert
/// rather than something to re-run until it looks right.
///
/// The split matters: the **winner is chosen first**, and the reel is then built to end on it. The
/// animation is therefore pure presentation — it cannot change the answer, and a reel that got cut
/// short or overshot would still name the film the picker chose.
public enum WatchlistRandomizer {

    public struct Spin: Sendable, Equatable, Identifiable {
        /// A fresh id per spin, so "Spin Again" re-presents rather than reusing the old reel.
        public let id = UUID()

        /// The film the spin landed on.
        public let winner: WatchlistEntry
        /// What the reel shows, in order. The last frame IS the winner.
        public let reel: [WatchlistEntry]

        public static func == (a: Spin, b: Spin) -> Bool {
            a.winner == b.winner && a.reel == b.reel
        }

        public init(winner: WatchlistEntry, reel: [WatchlistEntry]) {
            self.winner = winner
            self.reel = reel
        }
    }

    /// How many frames the reel runs for. Enough to read as a spin rather than a cut, and short
    /// enough that "again" stays cheap.
    public static let reelLength = 26

    /// Films a spin may land on: matched to TMDB, still on the list, and carrying artwork.
    ///
    /// An unmatched film has no page to open and no poster to show — landing on one is a dead end
    /// dressed up as a result, so it is not eligible even though it is on the watchlist.
    public static func eligible(_ entries: [WatchlistEntry]) -> [WatchlistEntry] {
        entries.filter { !$0.isRemoved && $0.tmdbID != nil && $0.posterPath?.isEmpty == false }
    }

    /// Nil when there is nothing worth spinning over.
    public static func spin<G: RandomNumberGenerator>(over entries: [WatchlistEntry],
                                                      using generator: inout G) -> Spin? {
        let pool = eligible(entries)
        guard let winner = pool.randomElement(using: &generator) else { return nil }
        return Spin(winner: winner, reel: reel(to: winner, from: pool, using: &generator))
    }

    /// The frames, ending on the winner.
    ///
    /// Consecutive duplicates are avoided because a repeated frame reads as the reel having
    /// stalled rather than spun — which matters most with a short pool, where random draws collide
    /// often. With only one eligible film there is nothing to vary, and the reel is that film.
    private static func reel<G: RandomNumberGenerator>(to winner: WatchlistEntry,
                                                       from pool: [WatchlistEntry],
                                                       using generator: inout G) -> [WatchlistEntry] {
        guard pool.count > 1 else { return Array(repeating: winner, count: reelLength) }

        var frames: [WatchlistEntry] = []
        frames.reserveCapacity(reelLength)

        // One short of the reel: the winner is appended last.
        while frames.count < reelLength - 1 {
            let candidates = pool.filter { $0.slug != frames.last?.slug }
            guard let next = candidates.randomElement(using: &generator) else { break }
            frames.append(next)
        }

        // The frame before the winner must not also be the winner, or the reel appears to stop
        // one frame early.
        if frames.last?.slug == winner.slug {
            if let swap = pool.filter({ $0.slug != winner.slug }).randomElement(using: &generator) {
                frames[frames.count - 1] = swap
            }
        }

        frames.append(winner)
        return frames
    }
}
