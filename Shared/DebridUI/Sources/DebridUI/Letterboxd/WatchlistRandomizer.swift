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
        /// What the reel shows, in order.
        public let reel: [WatchlistEntry]
        /// Where the reel comes to rest. Deliberately NOT the last frame — see `framesPastWinner`.
        public let winnerIndex: Int

        public static func == (a: Spin, b: Spin) -> Bool {
            a.winner == b.winner && a.reel == b.reel && a.winnerIndex == b.winnerIndex
        }

        public init(winner: WatchlistEntry, reel: [WatchlistEntry], winnerIndex: Int) {
            self.winner = winner
            self.reel = reel
            self.winnerIndex = winnerIndex
        }
    }

    /// How far the reel travels before settling. Enough to read as a spin rather than a cut, and
    /// short enough that "again" stays cheap.
    public static let framesBeforeWinner = 30

    /// Frames kept queued up PAST the winner.
    ///
    /// A wheel comes to rest; it does not run out of wheel. Ending the reel on the winner meant
    /// the strip visibly emptied on its trailing side as it slowed — the film had nothing coming
    /// after it, which reads as the animation reaching the end of its data rather than losing
    /// momentum. These are the films you see sitting next to the one it picked.
    ///
    /// Matches the spinner's visible radius, so the trailing side is full at rest.
    public static let framesPastWinner = 4

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
        let frames = reel(to: winner, from: pool, using: &generator)
        return Spin(winner: winner, reel: frames, winnerIndex: framesBeforeWinner)
    }

    /// The frames, ending on the winner.
    ///
    /// Consecutive duplicates are avoided because a repeated frame reads as the reel having
    /// stalled rather than spun — which matters most with a short pool, where random draws collide
    /// often. With only one eligible film there is nothing to vary, and the reel is that film.
    private static func reel<G: RandomNumberGenerator>(to winner: WatchlistEntry,
                                                       from pool: [WatchlistEntry],
                                                       using generator: inout G) -> [WatchlistEntry] {
        let total = framesBeforeWinner + 1 + framesPastWinner
        guard pool.count > 1 else { return Array(repeating: winner, count: total) }

        var frames: [WatchlistEntry] = []
        frames.reserveCapacity(total)

        // Run-up, then the winner at `framesBeforeWinner`, then the films that carry on past it.
        // Consecutive duplicates are avoided throughout, because a repeated frame reads as the
        // reel having stalled rather than spun — which matters most with a short pool, where
        // random draws collide often.
        while frames.count < total {
            let isWinnerSlot = frames.count == framesBeforeWinner
            let candidates = isWinnerSlot
                ? [winner]
                : pool.filter { $0.slug != frames.last?.slug && $0.slug != nextFixedSlug(at: frames.count, winner: winner) }
            guard let next = candidates.randomElement(using: &generator)
                    ?? pool.filter({ $0.slug != frames.last?.slug }).randomElement(using: &generator)
            else { break }
            frames.append(next)
        }

        return frames
    }

    /// The winner's slug when the NEXT slot is the winner's, so the frame before it is never the
    /// same film — the reel would otherwise appear to have already stopped.
    private static func nextFixedSlug(at index: Int, winner: WatchlistEntry) -> String? {
        index + 1 == framesBeforeWinner ? winner.slug : nil
    }
}
